import Foundation

/// One event emitted by an agent (today: a Claude Code hook) and sent to the app.
public struct AgentEvent: Codable, Sendable {
    public var agent: String
    public var sessionId: String
    public var cwd: String?
    public var event: String
    public var tool: String?
    public var message: String?
    /// Parent process of the hook: for Claude Code, the agent itself or its shell. Lets us detect dead sessions later.
    public var pid: Int?
    /// Identifies one tool call across its events, so a pending question can be matched to the call that ended.
    public var toolUseId: String?
    /// For notifications, why the agent is notifying: "permission_prompt", "idle_prompt", "agent_completed"...
    public var kind: String?
    /// How the session handles permissions: "default", "acceptEdits", "plan", "bypassPermissions"...
    public var permissionMode: String?
    /// Present only when the hook is waiting for an answer on the same connection.
    public var permission: PermissionPrompt?
    /// Where the agent writes this conversation. It also records the conversation's name, so the island can show it.
    public var transcriptPath: String?
    public var timestamp: Date

    public init(agent: String, sessionId: String, cwd: String?, event: String,
                tool: String?, message: String?, pid: Int? = nil, toolUseId: String? = nil, kind: String? = nil, permissionMode: String? = nil,
                permission: PermissionPrompt? = nil, transcriptPath: String? = nil, timestamp: Date = Date()) {
        self.agent = agent
        self.sessionId = sessionId
        self.cwd = cwd
        self.event = event
        self.tool = tool
        self.message = message
        self.pid = pid
        self.toolUseId = toolUseId
        self.kind = kind
        self.permissionMode = permissionMode
        self.permission = permission
        self.transcriptPath = transcriptPath
        self.timestamp = timestamp
    }
}

public extension AgentEvent {
    /// Fractional seconds on the wire: async hooks often land within the same second, and their order matters.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

/// Everything iSland keeps on disk lives in ~/.island, a short path without spaces:
/// the socket path must stay under 104 bytes, and the hook command goes through a shell.
public enum IslandPaths {
    /// `ISLAND_HOME` relocates everything (socket, helper) so tests never touch a running instance.
    public static var home: URL {
        if let override = ProcessInfo.processInfo.environment["ISLAND_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".island", isDirectory: true)
    }
    public static var socketURL: URL { home.appendingPathComponent("island.sock") }
    public static var hookBinaryURL: URL {
        home.appendingPathComponent("bin", isDirectory: true).appendingPathComponent("island-hook")
    }
    public static var claudeSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }
}
