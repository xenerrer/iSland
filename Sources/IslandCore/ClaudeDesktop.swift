import Foundation

/// A chat in the Code tab of the Claude desktop app.
public struct DesktopChat: Equatable, Sendable {
    /// `local_<uuid>`: the id the app uses to open this chat.
    public var localId: String
    /// The id Claude Code itself uses for the conversation (`session_id` in hook payloads).
    public var cliSessionId: String
    /// The name shown in the app's sidebar.
    public var title: String?
    public var isArchived: Bool

    public init(localId: String, cliSessionId: String, title: String?, isArchived: Bool = false) {
        self.localId = localId
        self.cliSessionId = cliSessionId
        self.title = title
        self.isArchived = isArchived
    }
}

public enum ClaudeDesktop {
    public static let bundleIdentifier = "com.anthropic.claudefordesktop"

    /// Where the app keeps one small JSON file per chat: `<account>/<organization>/local_<uuid>.json`.
    /// `ISLAND_CLAUDE_CHATS` relocates it, which is how the tests stay away from the real one.
    public static var chatsFolder: URL {
        if let override = ProcessInfo.processInfo.environment["ISLAND_CLAUDE_CHATS"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)
    }

    /// The app's own "open this chat" link, handled by the app itself (`claude://code/continue?session=local_...`).
    /// Anything that is not shaped like a chat id is refused, so nothing odd ever reaches the app.
    public static func deepLink(toChat localId: String) -> URL? {
        guard isChatId(localId) else { return nil }
        return URL(string: "claude://code/continue?session=" + localId)
    }

    /// The app's "new chat in this folder" link (`claude://code/new?folder=...`). Only absolute paths are accepted.
    public static func newChatLink(inFolder path: String) -> URL? {
        guard path.hasPrefix("/"), path.utf8.count < 1024, !path.unicodeScalars.contains(where: { $0.value < 32 }) else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/")
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "claude://code/new?folder=" + encoded)
    }

    /// `local_` followed by 1...64 letters, digits or dashes: the shape the app itself accepts.
    static func isChatId(_ id: String) -> Bool {
        guard id.hasPrefix("local_") else { return false }
        let rest = id.dropFirst("local_".count)
        return (1...64).contains(rest.count) && rest.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}

public enum SessionTitle {
    /// One tidy line: newlines folded into spaces, trimmed, bounded. nil when nothing is left.
    public static func clean(_ raw: String) -> String? {
        let oneLine = raw.split(whereSeparator: \.isNewline).joined(separator: " ")
        let trimmed = oneLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(200))
    }
}

/// Finds chats by their Claude Code session id while reading as little as possible. The app's store holds about
/// 500 KB per chat (tool lists, snapshots), mostly dead weight for us, and only a few chats are on screen at a time:
/// so every file is only asked for its ids (the first bytes), and a whole record is read only for a chat that is
/// wanted, and only again when the file changes.
public final class DesktopChatIndex: @unchecked Sendable {
    private struct Entry {
        var headModified: Date?
        var cliSessionId: String?
        /// Where the chat works (the original folder for a worktree): what the sidebar groups by.
        var folder: String?
        var chat: DesktopChat?
        var chatModified: Date?
    }

    private let root: URL
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init(root: URL = ClaudeDesktop.chatsFolder) {
        self.root = root
    }

    /// The chats behind these Claude Code session ids. Ids that match no chat (a session started in a terminal)
    /// are left out. Safe to call from any thread.
    public func chats(forSessions wanted: Set<String>) -> [String: DesktopChat] {
        guard !wanted.isEmpty else { return [:] }
        lock.lock()
        defer { lock.unlock() }
        var seen = Set<String>()
        var found: [String: DesktopChat] = [:]
        for (url, modified) in chatFiles() {
            let path = url.path
            seen.insert(path)
            var entry = loadHead(of: url, modified: modified)
            if let id = entry.cliSessionId, wanted.contains(id), entry.chatModified != modified,
               let chat = Self.parseRecord(try? Data(contentsOf: url)) {
                entry.chat = chat // a record caught mid-write fails to parse: keep the old one and try again next time
                entry.chatModified = modified
            }
            entries[path] = entry
            guard let id = entry.cliSessionId, wanted.contains(id), let chat = entry.chat else { continue }
            // The same conversation can sit in two records (a fork, a restored archive): prefer the live one.
            if let existing = found[id], !existing.isArchived || chat.isArchived { continue }
            found[id] = chat
        }
        entries = entries.filter { seen.contains($0.key) }
        return found
    }

    /// The folders you worked in most recently, newest first, for "new chat here". Folders that no longer exist are left out.
    public func recentFolders(limit: Int = 6) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        var seen = Set<String>()
        var folders: [String] = []
        for (url, modified) in chatFiles().sorted(by: { $0.modified > $1.modified }) {
            guard let folder = loadHead(of: url, modified: modified).folder, seen.insert(folder).inserted else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            folders.append(folder)
            if folders.count == limit { break }
        }
        return folders
    }

    // MARK: Reading

    /// What the first bytes of a record say, cached while the file keeps its modification date. Call with the lock held.
    private func loadHead(of url: URL, modified: Date) -> Entry {
        var entry = entries[url.path] ?? Entry()
        if entry.headModified != modified {
            let head = String(decoding: Self.readHead(of: url), as: UTF8.self)
            entry.cliSessionId = Self.stringValue(forKey: "cliSessionId", inHead: head).flatMap { $0.isEmpty ? nil : $0 }
            entry.folder = Self.stringValue(forKey: "originCwd", inHead: head) ?? Self.stringValue(forKey: "cwd", inHead: head)
            entry.headModified = modified
            entries[url.path] = entry
        }
        return entry
    }

    private func chatFiles() -> [(url: URL, modified: Date)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey, .isDirectoryKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return [] }
        var files: [(URL, Date)] = []
        for case let url as URL in walker {
            let name = url.lastPathComponent
            if walker.level > 4 || name.hasPrefix("deleted_") { walker.skipDescendants(); continue }
            guard name.hasPrefix("local_"), url.pathExtension == "json",
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let modified = values.contentModificationDate else { continue }
            files.append((url, modified))
        }
        return files
    }

    private static func readHead(of url: URL) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 1024)) ?? Data()
    }

    /// A top-level string value among the first bytes of a record, e.g. `"cwd":"/Users/me/project"`. nil when the key is
    /// missing, the value is cut off by the end of what was read, or it uses an escape other than \\ and \".
    static func stringValue(forKey key: String, inHead text: String) -> String? {
        guard let start = text.range(of: "\"\(key)\":\"") else { return nil }
        var value = ""
        var escaped = false
        for character in text[start.upperBound...] {
            if escaped {
                guard character == "\"" || character == "\\" || character == "/" else { return nil }
                value.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                return value
            } else {
                value.append(character)
            }
        }
        return nil
    }

    static func parseRecord(_ data: Data?) -> DesktopChat? {
        guard let data, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let localId = object["sessionId"] as? String, ClaudeDesktop.isChatId(localId),
              let cli = object["cliSessionId"] as? String, !cli.isEmpty else { return nil }
        return DesktopChat(localId: localId, cliSessionId: cli,
                           title: (object["title"] as? String).flatMap(SessionTitle.clean),
                           isArchived: object["isArchived"] as? Bool ?? false)
    }
}

/// The name of a conversation as Claude Code recorded it in the transcript: the Claude app and `/rename` both
/// append a "custom-title" entry (and named agents an "agent-name" one), repeated every few turns. A fallback for
/// chats that did not start in the Claude app, which have no record there.
public enum TranscriptTitle {
    static let tailBytes = 1_048_576

    public static func read(atPath path: String) -> String? {
        guard path.hasPrefix("/"), path.hasSuffix(".jsonl"), let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > UInt64(tailBytes) ? end - UInt64(tailBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let tail = try? handle.readToEnd() else { return nil }
        return title(inTail: tail)
    }

    /// The last title entry in a chunk taken from the end of a transcript.
    static func title(inTail data: Data) -> String? {
        let kinds: [(type: String, key: String)] = [("custom-title", "customTitle"), ("agent-name", "agentName")]
        var last: (position: Int, type: String, key: String)?
        for kind in kinds {
            let marker = Data("\"type\":\"\(kind.type)\"".utf8)
            if let found = data.range(of: marker, options: .backwards), found.lowerBound > (last?.position ?? -1) {
                last = (found.lowerBound, kind.type, kind.key)
            }
        }
        guard let last else { return nil }
        let lineStart = data[..<last.position].lastIndex(of: 0x0A).map { $0 + 1 } ?? data.startIndex
        let lineEnd = data[last.position...].firstIndex(of: 0x0A) ?? data.endIndex
        guard let object = (try? JSONSerialization.jsonObject(with: data[lineStart..<lineEnd])) as? [String: Any],
              object["type"] as? String == last.type, let value = object[last.key] as? String else { return nil }
        return SessionTitle.clean(value)
    }
}

/// Where and under what name the mirror's photos are saved.
public enum PhotoFiles {
    /// `iSland 2026-10-02 15.41.25.jpg` (dots in the time: a colon is not welcome in a file name).
    public static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "iSland %04d-%02d-%02d %02d.%02d.%02d.jpg", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// A path in `folder` that does not exist yet: two photos in the same second get " 2", " 3"...
    public static func uniqueURL(in folder: URL, for date: Date, calendar: Calendar = .current) -> URL {
        let name = fileName(for: date, calendar: calendar)
        var url = folder.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent((name as NSString).deletingPathExtension + " \(number).jpg")
            number += 1
        }
        return url
    }
}
