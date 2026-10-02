import Foundation

/// Translates between Claude Code's hook protocol and iSland's neutral one. Codex CLI speaks the same protocol (same fields,
/// same answer to a permission request), so it uses this too, under its own name.
/// Everything Claude-specific lives here, so supporting another agent means writing a sibling of this file.
public enum ClaudeHook {
    /// How long the hook waits for an answer in the island before handing the question back to the terminal.
    /// Claude Code runs PermissionRequest hooks *before* showing its own prompt, so this is also the longest
    /// the terminal prompt can be delayed when nobody answers in the island.
    public static let waitSeconds = 20

    /// Tools whose dialog is a conversation rather than a yes/no question. The island never answers these.
    static let conversational: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    public static func event(from payload: JSONValue, parentPid: Int? = nil, waitSeconds: Int = ClaudeHook.waitSeconds,
                             agent: AgentKind = .claude) -> AgentEvent {
        let name = payload["hook_event_name"]?.stringValue ?? "unknown"
        let tool = payload["tool_name"]?.stringValue
        var event = AgentEvent(
            agent: agent.rawValue,
            sessionId: payload["session_id"]?.stringValue ?? "unknown",
            cwd: payload["cwd"]?.stringValue,
            event: name,
            tool: tool,
            message: payload["message"]?.stringValue,
            pid: parentPid,
            toolUseId: payload["tool_use_id"]?.stringValue,
            kind: payload["notification_type"]?.stringValue,
            permissionMode: payload["permission_mode"]?.stringValue,
            transcriptPath: payload["transcript_path"]?.stringValue)
        if name == "PermissionRequest", let tool, !conversational.contains(tool) {
            event.permission = prompt(tool: tool, input: payload["tool_input"],
                                      suggestion: selectedSuggestion(payload["permission_suggestions"]),
                                      waitSeconds: waitSeconds)
        }
        return event
    }

    /// What Claude Code expects on stdout for a PermissionRequest hook. nil means "print nothing": the terminal asks.
    public static func stdout(for decision: Decision, payload: JSONValue) -> String? {
        var inner: [JSONMember]
        switch decision {
        case .terminal:
            return nil
        case .allow:
            inner = [JSONMember("behavior", .string("allow"))]
        case .allowAlways:
            inner = [JSONMember("behavior", .string("allow"))]
            if let suggestion = selectedSuggestion(payload["permission_suggestions"]) {
                inner.append(JSONMember("updatedPermissions", .array([suggestion])))
            }
        case .deny:
            inner = [
                JSONMember("behavior", .string("deny")),
                JSONMember("message", .string("The user denied this request from the iSland notch.")),
            ]
        }
        let root = JSONValue.object([
            JSONMember("hookSpecificOutput", .object([
                JSONMember("hookEventName", .string("PermissionRequest")),
                JSONMember("decision", .object(inner)),
            ])),
        ])
        return root.compact()
    }

    // MARK: - Prompt text

    static func prompt(tool: String, input: JSONValue?, suggestion: JSONValue?, waitSeconds: Int) -> PermissionPrompt {
        let (title, detail) = describe(tool: tool, input: input)
        let (clean, hidesSomething) = DisplayText.sanitized(truncated(detail, to: 600))
        // Whatever the card cannot show in full, the person cannot judge: no one-click yes for it.
        let review = hidesSomething || detail.count > 600 || PermissionPrompt.estimatedLines(of: clean) > PermissionPrompt.visibleLines
        return PermissionPrompt(tool: tool, title: title, detail: clean, alwaysLabel: suggestion.map(label(for:)),
                                waitSeconds: waitSeconds, needsReview: review)
    }

    static func describe(tool: String, input: JSONValue?) -> (title: String, detail: String) {
        func field(_ key: String) -> String { input?[key]?.stringValue ?? "" }
        switch tool {
        case "Bash": return ("Run command", field("command"))
        case "Edit", "MultiEdit": return ("Edit file", field("file_path"))
        case "Write": return ("Write file", field("file_path"))
        case "NotebookEdit": return ("Edit notebook", field("notebook_path"))
        case "Read": return ("Read file", field("file_path"))
        case "Glob": return ("Find files", field("pattern"))
        case "Grep": return ("Search files", field("pattern"))
        case "WebFetch": return ("Fetch page", field("url"))
        case "WebSearch": return ("Search the web", field("query"))
        default:
            let body = input?.compact() ?? ""
            if tool.hasPrefix("mcp__") {
                let parts = tool.dropFirst(5).components(separatedBy: "__")
                if parts.count >= 2 { return ("\(parts[0]) · \(parts.dropFirst().joined(separator: " "))", body) }
            }
            return (tool, body)
        }
    }

    static func truncated(_ text: String, to limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    // MARK: - Always allow

    /// The one suggestion the "always allow" button applies: the first rule that would be added.
    /// Only one, so the button never does more than its label promises.
    static func selectedSuggestion(_ suggestions: JSONValue?) -> JSONValue? {
        suggestions?.arrayValue?.first { $0["type"]?.stringValue == "addRules" }
    }

    /// e.g. "Always allow Bash(npm test:*)"
    static func label(for suggestion: JSONValue) -> String {
        let rules = suggestion["rules"]?.arrayValue ?? []
        let names = rules.compactMap { rule -> String? in
            guard let tool = rule["toolName"]?.stringValue else { return nil }
            if let content = rule["ruleContent"]?.stringValue, !content.isEmpty { return "\(tool)(\(content))" }
            return tool
        }
        return names.isEmpty ? "Always allow" : "Always allow " + names.joined(separator: ", ")
    }
}
