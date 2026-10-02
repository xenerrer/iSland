import Foundation

/// The coding agents iSland can follow. Each one tells its hooks to the same helper, which says which agent is speaking.
public enum AgentKind: String, CaseIterable, Sendable {
    case claude, codex, gemini

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex CLI"
        case .gemini: "Gemini CLI"
        }
    }

    /// One hook to register: the agent's own name for the event, and whether it waits for iSland's answer.
    public struct Hook: Equatable, Sendable {
        public let name: String
        public let blocking: Bool
    }

    /// The events iSland listens to, with each agent's own names. Only the ones the agent's documentation lists, because an
    /// unknown event name in a config file can make the agent reject the whole file.
    public var hooks: [Hook] {
        func plain(_ names: [String], blocking: [String] = []) -> [Hook] {
            names.map { Hook(name: $0, blocking: blocking.contains($0)) }
        }
        switch self {
        case .claude:
            return plain(["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification",
                          "PermissionRequest", "Stop"], blocking: ["PermissionRequest"])
        case .codex:
            return plain(["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop"],
                         blocking: ["PermissionRequest"])
        case .gemini:
            // Gemini's hooks run in the agent's loop and have no approval protocol we can rely on: status only.
            return plain(["SessionStart", "SessionEnd", "BeforeAgent", "BeforeTool", "AfterTool", "AfterAgent", "Notification"])
        }
    }

    /// The agent's own folder in the home directory.
    public func configFolder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".\(rawValue)", isDirectory: true)
    }

    /// The file the hooks are registered in. (Codex reads `hooks.json` next to its `config.toml`.)
    public func settingsURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        configFolder(home: home).appendingPathComponent(self == .codex ? "hooks.json" : "settings.json")
    }

    /// What follows the helper's path in the registered command, so the helper knows who is calling.
    public var commandArguments: String { self == .claude ? "" : " --agent \(rawValue)" }

    /// `--agent codex` among a program's arguments.
    public init?(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "--agent"), index + 1 < arguments.count,
              let kind = AgentKind(rawValue: arguments[index + 1]) else { return nil }
        self = kind
    }

    /// Whether the agent seems to be installed here: it has left its folder in the home directory, or its program sits
    /// in a place such programs usually go. (No process is run: this only looks at files.)
    public func isInstalled(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            searchPath: [String] = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? [],
                            usualFolders: [String]? = nil) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: configFolder(home: home).path) { return true }
        var folders = searchPath + (usualFolders ?? ["/opt/homebrew/bin", "/usr/local/bin", home.appendingPathComponent(".local/bin").path,
                                                     home.appendingPathComponent(".npm-global/bin").path, home.appendingPathComponent(".bun/bin").path])
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? fm.contentsOfDirectory(atPath: nvm.path) {
            folders += versions.map { nvm.appendingPathComponent($0).appendingPathComponent("bin").path }
        }
        return folders.contains { fm.isExecutableFile(atPath: $0 + "/" + rawValue) }
    }
}
