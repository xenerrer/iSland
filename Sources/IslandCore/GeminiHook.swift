import Foundation

/// Translates Gemini CLI's hook payloads into iSland's neutral events. Gemini's events have other names and its tools too;
/// both are mapped to the ones the rest of the app already knows. Status only: iSland does not answer Gemini's questions.
public enum GeminiHook {
    static let events: [String: String] = [
        "SessionStart": "SessionStart", "SessionEnd": "SessionEnd", "BeforeAgent": "UserPromptSubmit",
        "BeforeTool": "PreToolUse", "AfterTool": "PostToolUse", "AfterAgent": "Stop", "Notification": "Notification",
    ]

    static let tools: [String: String] = [
        "run_shell_command": "Bash", "write_file": "Write", "replace": "Edit", "read_file": "Read", "read_many_files": "Read",
        "list_directory": "LS", "glob": "Glob", "search_file_content": "Grep", "grep_search": "Grep",
        "web_fetch": "WebFetch", "google_web_search": "WebSearch",
    ]

    public static func event(from payload: JSONValue, parentPid: Int? = nil) -> AgentEvent {
        let name = payload["hook_event_name"]?.stringValue ?? "unknown"
        let tool = payload["tool_name"]?.stringValue
        var kind: String?
        if name == "Notification" {
            // "ToolPermission" is Gemini asking whether it may use a tool: the same as Claude's permission prompt.
            kind = payload["notification_type"]?.stringValue == "ToolPermission" ? "permission_prompt" : payload["notification_type"]?.stringValue
        }
        return AgentEvent(
            agent: AgentKind.gemini.rawValue,
            sessionId: payload["session_id"]?.stringValue ?? "unknown",
            cwd: payload["cwd"]?.stringValue,
            event: events[name] ?? name,
            tool: tool.map { tools[$0] ?? $0 },
            message: payload["message"]?.stringValue,
            pid: parentPid,
            kind: kind,
            transcriptPath: payload["transcript_path"]?.stringValue)
    }
}
