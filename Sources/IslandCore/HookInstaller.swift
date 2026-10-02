import Foundation

public enum HookInstallerError: Error, CustomStringConvertible {
    case unreadable(String)
    case invalid(String)
    case writeFailed(String)

    public var description: String {
        switch self {
        case .unreadable(let message), .invalid(let message), .writeFailed(let message): return message
        }
    }
}

/// Adds or removes iSland's hooks in an agent's hooks file (Claude Code's settings.json, Codex's hooks.json, Gemini CLI's
/// settings.json), touching nothing else.
///
/// Guarantees: it parses with an order-preserving reader, refuses to write anything that does not re-parse,
/// verifies that every setting outside "hooks" is byte-for-byte identical in meaning and order, backs the file
/// up before changing it, and writes atomically. Hooks added by other tools are never modified.
public struct HookInstaller {
    /// Claude Code's events. All are fire-and-forget (async) except PermissionRequest, which waits for your answer.
    public static let events = AgentKind.claude.hooks.map(\.name)

    /// The events of the agent this installer serves.
    public var events: [String] { kind.hooks.map(\.name) }

    public struct Change {
        /// Full file content after the change.
        public let text: String
        /// Events where iSland's hook was added, updated or removed.
        public let changed: [String]
        public let unchanged: [String]
        public var didChange: Bool { !changed.isEmpty }
    }

    public let kind: AgentKind
    public let settingsURL: URL
    public let hookPath: String

    public init(kind: AgentKind = .claude, settingsURL: URL? = nil, hookPath: String = IslandPaths.hookBinaryURL.path) {
        self.kind = kind
        self.settingsURL = settingsURL ?? kind.settingsURL()
        self.hookPath = hookPath
    }

    /// Computes the file after installing/uninstalling, without touching the disk.
    public func preview(install: Bool) throws -> Change {
        let (root, trailingNewline) = try load()
        guard case .object(let before) = root else { throw HookInstallerError.invalid("settings must be a JSON object") }

        var hooks: JSONValue = .object([])
        if let existing = root["hooks"] {
            guard case .object = existing else { throw HookInstallerError.invalid("\"hooks\" in settings is not an object") }
            hooks = existing
        }

        var changed: [String] = []
        var unchanged: [String] = []
        for event in events {
            var groups: [JSONValue] = []
            if let existing = hooks[event] {
                guard case .array(let array) = existing else {
                    throw HookInstallerError.invalid("\"hooks.\(event)\" in settings is not an array")
                }
                groups = array
            }
            let (updated, didChange) = install ? installing(into: groups, event: event) : removing(from: groups)
            guard didChange else { unchanged.append(event); continue }
            changed.append(event)
            hooks[event] = updated.isEmpty ? nil : .array(updated)
        }

        var newRoot = root
        if !changed.isEmpty {
            if case .object(let members) = hooks, members.isEmpty {
                newRoot["hooks"] = nil
            } else {
                newRoot["hooks"] = hooks
            }
        }

        guard case .object(let after) = newRoot,
              before.filter({ $0.key != "hooks" }) == after.filter({ $0.key != "hooks" })
        else { throw HookInstallerError.invalid("internal error: refusing to modify settings outside \"hooks\"") }

        let text = newRoot.serialized() + (trailingNewline ? "\n" : "")
        return Change(text: text, changed: changed, unchanged: unchanged)
    }

    /// Applies the change. Returns the change and the backup file created (nil when there was nothing to do).
    @discardableResult
    public func apply(install: Bool) throws -> (change: Change, backup: URL?) {
        let change = try preview(install: install)
        guard change.didChange else { return (change, nil) }

        guard let data = change.text.data(using: .utf8), (try? JSONValue.parse(data)) != nil else {
            throw HookInstallerError.invalid("internal error: generated settings are not valid JSON")
        }

        let fm = FileManager.default
        let target = settingsURL.resolvingSymlinksInPath()
        var backup: URL?
        var permissions: Any = 0o600

        if fm.fileExists(atPath: target.path) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            var candidate = target.deletingLastPathComponent()
                .appendingPathComponent("\(target.lastPathComponent).island-backup-\(formatter.string(from: Date()))")
            var suffix = 1
            while fm.fileExists(atPath: candidate.path) {
                suffix += 1
                candidate = candidate.deletingLastPathComponent()
                    .appendingPathComponent("\(target.lastPathComponent).island-backup-\(formatter.string(from: Date()))-\(suffix)")
            }
            do { try fm.copyItem(at: target, to: candidate) } catch {
                throw HookInstallerError.writeFailed("could not create backup: \(error.localizedDescription)")
            }
            backup = candidate
            if let attributes = try? fm.attributesOfItem(atPath: target.path), let mode = attributes[.posixPermissions] {
                permissions = mode
            }
        } else {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        let temporary = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).island-tmp")
        do {
            try data.write(to: temporary)
            try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporary.path)
            if fm.fileExists(atPath: target.path) {
                _ = try fm.replaceItemAt(target, withItemAt: temporary)
            } else {
                try fm.moveItem(at: temporary, to: target)
            }
        } catch {
            try? fm.removeItem(at: temporary)
            throw HookInstallerError.writeFailed("could not write settings: \(error.localizedDescription)")
        }
        return (change, backup)
    }

    /// Events for which iSland's hook is currently registered.
    public func registeredEvents() throws -> [String] {
        let (root, _) = try load()
        guard let hooks = root["hooks"] else { return [] }
        return events.filter { event in
            guard case .array(let groups)? = hooks[event] else { return false }
            return groups.contains { group in
                guard case .array(let entries)? = group["hooks"] else { return false }
                return entries.contains(where: isOurs)
            }
        }
    }

    /// Whether any agent still has iSland's hooks registered, in its default file. The helper stays while one does.
    public static func anyInstalled(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        AgentKind.allCases.contains { kind in
            let installer = HookInstaller(kind: kind, settingsURL: kind.settingsURL(home: home))
            return !((try? installer.registeredEvents()) ?? []).isEmpty
        }
    }

    // MARK: - Internals

    /// The command exactly as written in settings.json: shell-quoted only when the path needs it.
    var command: String { Self.shellQuoted(hookPath) + kind.commandArguments }

    func ourEntry(for event: String) -> JSONValue {
        let blocking = kind.hooks.first { $0.name == event }?.blocking ?? false
        if kind == .gemini {
            // Gemini names its hooks and counts the timeout in milliseconds; its hooks run in the agent's loop, so ours is quick.
            return .object([
                JSONMember("name", .string("island")),
                JSONMember("type", .string("command")),
                JSONMember("command", .string(command)),
                JSONMember("timeout", .number("10000")),
            ])
        }
        var members = [
            JSONMember("type", .string("command")),
            JSONMember("command", .string(command)),
        ]
        if blocking {
            // Blocks while the user decides in the island. The agent runs this before its own prompt, and
            // kills the hook at `timeout`, so it must outlast the hook's own wait.
            members.append(JSONMember("timeout", .number(String(ClaudeHook.waitSeconds + 10))))
        } else {
            members.append(JSONMember("async", .bool(true)))
            members.append(JSONMember("timeout", .number("10")))
        }
        return .object(members)
    }

    func isOurs(_ entry: JSONValue) -> Bool {
        guard case .string(let value)? = entry["command"] else { return false }
        return value == command || (kind == .claude && value == hookPath)
    }

    func installing(into groups: [JSONValue], event: String) -> ([JSONValue], Bool) {
        var groups = groups
        let desired = ourEntry(for: event)
        for groupIndex in groups.indices {
            guard case .array(var entries)? = groups[groupIndex]["hooks"] else { continue }
            for entryIndex in entries.indices where isOurs(entries[entryIndex]) {
                if entries[entryIndex] == desired { return (groups, false) }
                entries[entryIndex] = desired
                groups[groupIndex]["hooks"] = .array(entries)
                return (groups, true)
            }
        }
        groups.append(.object([JSONMember("hooks", .array([desired]))]))
        return (groups, true)
    }

    func removing(from groups: [JSONValue]) -> ([JSONValue], Bool) {
        var changed = false
        var result: [JSONValue] = []
        for var group in groups {
            guard case .array(let entries)? = group["hooks"] else { result.append(group); continue }
            let kept = entries.filter { !isOurs($0) }
            if kept.count == entries.count { result.append(group); continue }
            changed = true
            if kept.isEmpty { continue } // the group existed only for us
            group["hooks"] = .array(kept)
            result.append(group)
        }
        return (result, changed)
    }

    private func load() throws -> (root: JSONValue, trailingNewline: Bool) {
        let url = settingsURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: url.path) else { return (.object([]), true) }
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            throw HookInstallerError.unreadable("could not read \(url.path): \(error.localizedDescription)")
        }
        if data.allSatisfy({ [0x20, 0x09, 0x0A, 0x0D].contains($0) }) { return (.object([]), true) }
        let root: JSONValue
        do { root = try JSONValue.parse(data) } catch {
            throw HookInstallerError.invalid("\(url.path) is not valid JSON, leaving it untouched: \(error)")
        }
        guard case .object = root else {
            throw HookInstallerError.invalid("\(url.path) must contain a JSON object, leaving it untouched")
        }
        return (root, data.last == 0x0A)
    }

    static func shellQuoted(_ path: String) -> String {
        let plain = path.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "/._-".unicodeScalars.contains($0) }
        return plain ? path : "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Puts the hook helper at its stable path, so settings.json never depends on where the app lives.
public enum HookBinary {
    public static func install(from source: URL, to destination: URL = IslandPaths.hookBinaryURL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: IslandPaths.home, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".island-hook.tmp")
        try? fm.removeItem(at: temporary)
        try fm.copyItem(at: source, to: temporary)
        // A downloaded app may carry the quarantine flag; our own helper must be runnable by the agent.
        removexattr(temporary.path, "com.apple.quarantine", 0)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fm.moveItem(at: temporary, to: destination)
        }
    }

    public static func remove(at url: URL = IslandPaths.hookBinaryURL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Next to the executable when running from a build folder, in Contents/Helpers inside the .app bundle.
    public static func bundledHelperURL() -> URL? {
        guard let executable = Bundle.main.executableURL else { return nil }
        let directory = executable.deletingLastPathComponent()
        let candidates = [
            directory.appendingPathComponent("island-hook"),
            directory.deletingLastPathComponent().appendingPathComponent("Helpers/island-hook"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Keeps the installed helper in step with the app that ships it (an app update must not leave a stale helper
    /// speaking an old protocol). Does nothing when the user never installed the hooks.
    public static func refreshIfInstalled(from source: URL, at destination: URL = IslandPaths.hookBinaryURL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: destination.path),
              !fm.contentsEqual(atPath: source.path, andPath: destination.path) else { return }
        try? install(from: source, to: destination)
    }
}
