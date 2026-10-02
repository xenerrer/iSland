import Foundation
import Testing
@testable import IslandCore

@Suite("Agents") struct AgentsTests {
    let home: URL

    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("island-agents-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    func parse(_ json: String) throws -> JSONValue { try JSONValue.parse(Data(json.utf8)) }

    // MARK: Catalog

    @Test func eachAgentHasItsOwnFileAndEvents() {
        #expect(AgentKind.claude.settingsURL(home: home).lastPathComponent == "settings.json")
        #expect(AgentKind.codex.settingsURL(home: home).path.hasSuffix(".codex/hooks.json"))
        #expect(AgentKind.gemini.settingsURL(home: home).path.hasSuffix(".gemini/settings.json"))
        #expect(AgentKind.codex.hooks.map(\.name) == ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop"])
        #expect(AgentKind.gemini.hooks.map(\.name).contains("BeforeTool") && AgentKind.gemini.hooks.map(\.name).contains("AfterAgent"))
        // only Claude Code and Codex wait for an answer, and only on a permission request
        #expect(AgentKind.claude.hooks.filter(\.blocking).map(\.name) == ["PermissionRequest"])
        #expect(AgentKind.codex.hooks.filter(\.blocking).map(\.name) == ["PermissionRequest"])
        #expect(AgentKind.gemini.hooks.filter(\.blocking).isEmpty)
    }

    @Test func theHelperLearnsWhoIsCallingFromItsArguments() {
        #expect(AgentKind(arguments: ["island-hook", "--agent", "codex"]) == .codex)
        #expect(AgentKind(arguments: ["island-hook", "--agent", "gemini"]) == .gemini)
        #expect(AgentKind(arguments: ["island-hook"]) == nil)
        #expect(AgentKind(arguments: ["island-hook", "--agent", "nope"]) == nil)
        #expect(AgentKind(arguments: ["island-hook", "--agent"]) == nil)
        #expect(AgentKind.claude.commandArguments.isEmpty && AgentKind.codex.commandArguments == " --agent codex")
    }

    @Test func anAgentIsInstalledWhenItLeftItsFolderOrItsProgramIsAround() throws {
        #expect(!AgentKind.codex.isInstalled(home: home, searchPath: [], usualFolders: []))
        try FileManager.default.createDirectory(at: AgentKind.codex.configFolder(home: home), withIntermediateDirectories: true)
        #expect(AgentKind.codex.isInstalled(home: home, searchPath: [], usualFolders: []))
        #expect(!AgentKind.gemini.isInstalled(home: home, searchPath: [], usualFolders: []))
        // or a program called gemini in a folder on the path
        let bin = home.appendingPathComponent("somewhere/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let program = bin.appendingPathComponent("gemini")
        try Data("#!/bin/sh\n".utf8).write(to: program)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
        #expect(AgentKind.gemini.isInstalled(home: home, searchPath: [bin.path], usualFolders: []))
    }

    // MARK: Installing

    @Test func codexGetsTheSameShapeAsClaudeInItsOwnFile() throws {
        let url = AgentKind.codex.settingsURL(home: home)
        let installer = HookInstaller(kind: .codex, settingsURL: url, hookPath: "/Users/me/.island/bin/island-hook")
        try installer.apply(install: true)
        let root = try JSONValue.parse(try Data(contentsOf: url))
        let hooks = try #require(root["hooks"])
        #expect(installer.events == ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop"])
        for event in installer.events { #expect(hooks[event] != nil, "\(event)") }
        let entry = try #require(hooks["PreToolUse"]?.arrayValue?.first?["hooks"]?.arrayValue?.first)
        #expect(entry["command"]?.stringValue == "/Users/me/.island/bin/island-hook --agent codex")
        #expect(entry["async"]?.boolValue == true)
        let ask = try #require(hooks["PermissionRequest"]?.arrayValue?.first?["hooks"]?.arrayValue?.first)
        #expect(ask["async"] == nil) // the permission hook waits for you
        #expect(ask["timeout"]?.doubleValue == Double(ClaudeHook.waitSeconds + 10))
        #expect(try installer.registeredEvents() == installer.events)
    }

    @Test func geminiGetsNamedHooksWithMillisecondTimeouts() throws {
        let url = AgentKind.gemini.settingsURL(home: home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = """
        {
          "theme": "dark",
          "hooks": {
            "BeforeTool": [
              {
                "matcher": "write_file",
                "hooks": [
                  {
                    "name": "mine",
                    "type": "command",
                    "command": "/usr/bin/true"
                  }
                ]
              }
            ]
          }
        }

        """
        try Data(original.utf8).write(to: url)
        let installer = HookInstaller(kind: .gemini, settingsURL: url, hookPath: "/Users/me/.island/bin/island-hook")
        try installer.apply(install: true)
        let root = try JSONValue.parse(try Data(contentsOf: url))
        #expect(root["theme"]?.stringValue == "dark") // the rest is untouched
        let before = try #require(root["hooks"]?["BeforeTool"]?.arrayValue)
        #expect(before.count == 2) // the user's own hook is still there, ours was added beside it
        let ours = try #require(before.last?["hooks"]?.arrayValue?.first)
        #expect(ours["name"]?.stringValue == "island" && ours["timeout"]?.doubleValue == 10_000)
        #expect(ours["async"] == nil && ours["command"]?.stringValue == "/Users/me/.island/bin/island-hook --agent gemini")
        #expect(root["hooks"]?["AfterAgent"] != nil)
        // and uninstalling gives the file back exactly
        try installer.apply(install: false)
        #expect(try String(contentsOf: url, encoding: .utf8) == original)
    }

    @Test func theHelperStaysWhileAnyAgentStillUsesIt() throws {
        #expect(!HookInstaller.anyInstalled(home: home))
        let codex = HookInstaller(kind: .codex, settingsURL: AgentKind.codex.settingsURL(home: home))
        let gemini = HookInstaller(kind: .gemini, settingsURL: AgentKind.gemini.settingsURL(home: home))
        try codex.apply(install: true)
        try gemini.apply(install: true)
        #expect(HookInstaller.anyInstalled(home: home))
        try codex.apply(install: false)
        #expect(HookInstaller.anyInstalled(home: home)) // Gemini still does
        try gemini.apply(install: false)
        #expect(!HookInstaller.anyInstalled(home: home))
    }

    // MARK: Translating

    @Test func codexSpeaksClaudesProtocolUnderItsOwnName() throws {
        let payload = try parse(#"""
        {"session_id":"c1","transcript_path":null,"cwd":"/work","hook_event_name":"PermissionRequest","model":"gpt-5","permission_mode":"default",
         "turn_id":"t","tool_name":"Bash","tool_input":{"command":"ls","description":"List"}}
        """#)
        let event = ClaudeHook.event(from: payload, agent: .codex)
        #expect(event.agent == "codex" && event.sessionId == "c1" && event.tool == "Bash")
        #expect(event.permission?.detail == "ls")
        #expect(ClaudeHook.stdout(for: .allow, payload: payload) != nil)
        #expect(ClaudeHook.event(from: payload).agent == "claude")
    }

    @Test func geminiEventsAreMappedToTheOnesTheAppKnows() throws {
        func event(_ json: String) throws -> AgentEvent { GeminiHook.event(from: try parse(json), parentPid: 9) }
        let tool = try event(#"{"session_id":"g1","cwd":"/w","hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"ls"}}"#)
        #expect(tool.agent == "gemini" && tool.event == "PreToolUse" && tool.tool == "Bash" && tool.pid == 9 && tool.sessionId == "g1")
        #expect(try event(#"{"session_id":"g","hook_event_name":"AfterTool","tool_name":"replace"}"#).tool == "Edit")
        #expect(try event(#"{"session_id":"g","hook_event_name":"BeforeAgent","prompt":"hi"}"#).event == "UserPromptSubmit")
        #expect(try event(#"{"session_id":"g","hook_event_name":"AfterAgent"}"#).event == "Stop")
        #expect(try event(#"{"session_id":"g","hook_event_name":"SessionEnd"}"#).event == "SessionEnd")
        let ask = try event(#"{"session_id":"g","hook_event_name":"Notification","notification_type":"ToolPermission","message":"Allow write?"}"#)
        #expect(ask.event == "Notification" && ask.kind == "permission_prompt" && ask.message == "Allow write?")
        // a tool or event it does not know passes through under its own name
        let odd = try event(#"{"hook_event_name":"PreCompress","tool_name":"custom_tool"}"#)
        #expect(odd.event == "PreCompress" && odd.tool == "custom_tool" && odd.sessionId == "unknown")
        #expect(odd.permission == nil)
    }
}
