import Foundation

/// How a tool (or any free text from an agent) is shown in a row. Agents name MCP tools `mcp__<server>__<tool>`, and the
/// server part can be a long id: a row has room for the tool only, and for a bounded amount of it.
public enum ToolName {
    public static let maxLength = 36

    /// `mcp__4380726e-b365_server__search_threads` -> `search_threads`; always at most `maxLength` characters.
    public static func display(_ raw: String) -> String {
        var name = raw
        if raw.hasPrefix("mcp__") {
            let parts = raw.dropFirst("mcp__".count).components(separatedBy: "__")
            if parts.count >= 2, let tool = parts.last, !tool.isEmpty { name = tool }
        }
        return clipped(name, to: maxLength)
    }

    /// At most `limit` characters, ending in an ellipsis when something was cut.
    public static func clipped(_ text: String, to limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(max(1, limit - 1))) + "…"
    }
}
