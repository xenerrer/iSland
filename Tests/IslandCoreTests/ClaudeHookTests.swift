import Foundation
import Testing
@testable import IslandCore

@Suite("ClaudeHook") struct ClaudeHookTests {
    static let bash = #"""
    {"session_id":"abc","cwd":"/Users/me/proj","hook_event_name":"PermissionRequest","tool_name":"Bash",
     "tool_input":{"command":"npm test"},"tool_use_id":"toolu_1",
     "permission_suggestions":[
       {"type":"setMode","mode":"acceptEdits","destination":"session"},
       {"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"npm test:*"}],"behavior":"allow","destination":"localSettings"}]}
    """#

    /// Captured from a live Claude Code session: no tool_use_id, a description, three kinds of suggestion.
    static let realShape = #"""
    {"session_id":"s","transcript_path":"/t","cwd":"/work/proj","scratchpad_dir":"/sp","prompt_id":"p","permission_mode":"default",
     "effort":{"level":"max"},"hook_event_name":"PermissionRequest","tool_name":"Bash",
     "tool_input":{"command":"touch /tmp/x && ls -la /tmp/x","description":"Create an empty file"},
     "permission_suggestions":[
       {"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"touch /tmp/x:*"},{"toolName":"Read","ruleContent":"/tmp/**"}],"behavior":"allow","destination":"localSettings"},
       {"type":"addDirectories","directories":["/tmp"],"destination":"session"},
       {"type":"setMode","mode":"acceptEdits","destination":"session"}]}
    """#

    func parse(_ json: String) throws -> JSONValue { try JSONValue.parse(Data(json.utf8)) }

    @Test func approvableToolsCarryAPrompt() throws {
        let event = ClaudeHook.event(from: try parse(Self.bash), parentPid: 7)
        let prompt = try #require(event.permission)
        #expect(event.sessionId == "abc")
        #expect(event.toolUseId == "toolu_1")
        #expect(event.pid == 7)
        #expect(prompt.title == "Run command")
        #expect(prompt.detail == "npm test")
        #expect(prompt.alwaysLabel == "Always allow Bash(npm test:*)")
        #expect(prompt.waitSeconds == ClaudeHook.waitSeconds)
    }

    @Test func theRealShapeWorksWithoutAToolUseId() throws {
        let payload = try parse(Self.realShape)
        let event = ClaudeHook.event(from: payload)
        let prompt = try #require(event.permission)
        #expect(event.toolUseId == nil)
        #expect(event.permissionMode == "default")
        #expect(prompt.detail == "touch /tmp/x && ls -la /tmp/x")
        #expect(prompt.alwaysLabel == "Always allow Bash(touch /tmp/x:*), Read(/tmp/**)")
        let inner = try decision(ClaudeHook.stdout(for: .allowAlways, payload: payload))
        let updated = try #require(inner["updatedPermissions"]?.arrayValue)
        #expect(updated.count == 1) // neither addDirectories nor setMode may sneak in
        #expect(updated[0]["rules"]?.arrayValue?.count == 2)
    }

    @Test func conversationalToolsAreNeverAnsweredFromTheIsland() throws {
        for tool in ["AskUserQuestion", "ExitPlanMode"] {
            let json = #"{"session_id":"a","hook_event_name":"PermissionRequest","tool_name":"\#(tool)","tool_input":{}}"#
            #expect(ClaudeHook.event(from: try parse(json)).permission == nil)
        }
    }

    @Test func otherEventsHaveNoPromptButKeepTheirIds() throws {
        let json = #"{"session_id":"a","cwd":"/p","hook_event_name":"PostToolUse","tool_name":"Edit","tool_use_id":"toolu_9"}"#
        let event = ClaudeHook.event(from: try parse(json))
        #expect(event.permission == nil)
        #expect(event.event == "PostToolUse")
        #expect(event.toolUseId == "toolu_9")
    }

    @Test func notificationTypesTravelWithTheEvent() throws {
        let json = #"{"session_id":"a","hook_event_name":"Notification","message":"waiting","notification_type":"idle_prompt"}"#
        let event = ClaudeHook.event(from: try parse(json))
        #expect(event.kind == "idle_prompt")
        #expect(event.message == "waiting")
    }

    @Test func thePermissionModeTravelsWithTheEvent() throws {
        let json = #"{"session_id":"a","hook_event_name":"PreToolUse","tool_name":"Bash","permission_mode":"bypassPermissions"}"#
        #expect(ClaudeHook.event(from: try parse(json)).permissionMode == "bypassPermissions")
    }

    @Test func missingFieldsDoNotCrash() throws {
        let event = ClaudeHook.event(from: try parse("{}"))
        #expect(event.sessionId == "unknown")
        #expect(event.event == "unknown")
    }

    func decision(_ output: String?) throws -> JSONValue {
        let text = try #require(output)
        #expect(!text.contains("\n"))
        let root = try parse(text)
        #expect(root["hookSpecificOutput"]?["hookEventName"]?.stringValue == "PermissionRequest")
        return try #require(root["hookSpecificOutput"]?["decision"])
    }

    @Test func allowPrintsAPlainAllow() throws {
        let inner = try decision(ClaudeHook.stdout(for: .allow, payload: try parse(Self.bash)))
        #expect(inner == .object([JSONMember("behavior", .string("allow"))]))
    }

    @Test func alwaysAllowAppliesOnlyTheFirstRuleSuggestion() throws {
        let inner = try decision(ClaudeHook.stdout(for: .allowAlways, payload: try parse(Self.bash)))
        #expect(inner["behavior"]?.stringValue == "allow")
        let updated = try #require(inner["updatedPermissions"]?.arrayValue)
        #expect(updated.count == 1) // the setMode suggestion must not sneak in
        #expect(updated[0]["type"]?.stringValue == "addRules")
        #expect(updated[0]["destination"]?.stringValue == "localSettings")
    }

    @Test func alwaysAllowWithoutSuggestionsDegradesToAllow() throws {
        let payload = try parse(#"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{}}"#)
        let inner = try decision(ClaudeHook.stdout(for: .allowAlways, payload: payload))
        #expect(inner["updatedPermissions"] == nil)
        #expect(inner["behavior"]?.stringValue == "allow")
    }

    @Test func denyCarriesAMessageForTheModel() throws {
        let inner = try decision(ClaudeHook.stdout(for: .deny, payload: try parse(Self.bash)))
        #expect(inner["behavior"]?.stringValue == "deny")
        #expect(inner["message"]?.stringValue?.isEmpty == false)
    }

    @Test func terminalPrintsNothing() throws {
        #expect(ClaudeHook.stdout(for: .terminal, payload: try parse(Self.bash)) == nil)
    }

    @Test func noRuleSuggestionMeansNoAlwaysButton() throws {
        let json = #"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"},"permission_suggestions":[{"type":"setMode","mode":"acceptEdits"}]}"#
        #expect(try #require(ClaudeHook.event(from: try parse(json)).permission).alwaysLabel == nil)
    }

    @Test func longDetailsAreKeptForTheCardToScrollAndHugeOnesAreCut() throws {
        // 5,000 characters fit what the card keeps: all of it can be read, so nothing is cut
        let long = String(repeating: "x", count: 5_000)
        let json = #"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"\#(long)"}}"#
        let kept = try #require(ClaudeHook.event(from: try parse(json)).permission)
        #expect(kept.detail.count == 5_000 && !kept.needsReview)
        // past the limit it is cut, marked, and cannot be approved from the island
        let huge = String(repeating: "x", count: 20_000)
        let hugeJson = #"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"\#(huge)"}}"#
        let cut = try #require(ClaudeHook.event(from: try parse(hugeJson)).permission)
        #expect(cut.detail.count == PermissionPrompt.maxDetailCharacters + 1)
        #expect(cut.detail.hasSuffix("…") && cut.needsReview)
    }

    @Test func mcpToolsGetReadableTitles() throws {
        let json = #"{"hook_event_name":"PermissionRequest","tool_name":"mcp__github__create_issue","tool_input":{"title":"Bug"}}"#
        let prompt = try #require(ClaudeHook.event(from: try parse(json)).permission)
        #expect(prompt.title == "github · create_issue")
        #expect(prompt.detail == #"{"title":"Bug"}"#)
    }
}
