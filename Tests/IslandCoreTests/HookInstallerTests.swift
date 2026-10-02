import Foundation
import Testing
@testable import IslandCore

@Suite("HookInstaller") struct HookInstallerTests {
    static let hook = "/Users/test/.island/bin/island-hook"

    /// A settings file in a fresh temp folder (or none when `content` is nil).
    func makeInstaller(_ content: String?, hookPath: String = hook) throws -> (installer: HookInstaller, url: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("island-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("settings.json")
        if let content { try content.write(to: url, atomically: true, encoding: .utf8) }
        return (HookInstaller(settingsURL: url, hookPath: hookPath), url)
    }

    static let withForeignHook = """
    {
      "model": "opus",
      "hooks": {
        "PreToolUse": [
          {
            "matcher": "Bash",
            "hooks": [
              {
                "type": "command",
                "command": "echo hi"
              }
            ]
          }
        ]
      },
      "theme": "dark"
    }

    """

    @Test func installCreatesTheFileWhenMissing() throws {
        let (installer, url) = try makeInstaller(nil)
        let (change, backup) = try installer.apply(install: true)
        #expect(change.changed == HookInstaller.events)
        #expect(backup == nil)
        #expect(try installer.registeredEvents() == HookInstaller.events)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func installKeepsEverythingElseAndForeignHooks() throws {
        let (installer, url) = try makeInstaller(Self.withForeignHook)
        try installer.apply(install: true)
        let root = try JSONValue.parse(try Data(contentsOf: url))
        #expect(root["model"] == .string("opus"))
        #expect(root["theme"] == .string("dark"))
        guard case .array(let groups)? = root["hooks"]?["PreToolUse"] else { Issue.record("PreToolUse missing"); return }
        #expect(groups.count == 2)
        #expect(groups[0]["matcher"] == .string("Bash"))
    }

    @Test func installIsIdempotent() throws {
        let (installer, url) = try makeInstaller(Self.withForeignHook)
        try installer.apply(install: true)
        let once = try String(contentsOf: url, encoding: .utf8)
        let (second, backup) = try installer.apply(install: true)
        #expect(!second.didChange)
        #expect(backup == nil)
        #expect(try String(contentsOf: url, encoding: .utf8) == once)
    }

    @Test func uninstallRestoresTheOriginalFileExactly() throws {
        let (installer, url) = try makeInstaller(Self.withForeignHook)
        try installer.apply(install: true)
        try installer.apply(install: false)
        #expect(try String(contentsOf: url, encoding: .utf8) == Self.withForeignHook)
        #expect(try installer.registeredEvents().isEmpty)
    }

    @Test func uninstallDropsTheHooksKeyWhenItEndsEmpty() throws {
        let original = "{\n  \"model\": \"opus\"\n}\n"
        let (installer, url) = try makeInstaller(original)
        try installer.apply(install: true)
        try installer.apply(install: false)
        #expect(try String(contentsOf: url, encoding: .utf8) == original)
    }

    @Test func backupIsCreatedBeforeChanging() throws {
        let (installer, url) = try makeInstaller(Self.withForeignHook)
        let (_, backup) = try installer.apply(install: true)
        let saved = try #require(backup)
        #expect(try String(contentsOf: saved, encoding: .utf8) == Self.withForeignHook)
        #expect(saved.deletingLastPathComponent() == url.deletingLastPathComponent())
    }

    @Test func refusesInvalidJSONAndLeavesItUntouched() throws {
        let broken = "{ \"model\": "
        let (installer, url) = try makeInstaller(broken)
        #expect(throws: HookInstallerError.self) { try installer.apply(install: true) }
        #expect(try String(contentsOf: url, encoding: .utf8) == broken)
    }

    @Test func refusesUnexpectedShapes() throws {
        let (installer, _) = try makeInstaller(#"{"hooks": []}"#)
        #expect(throws: HookInstallerError.self) { try installer.preview(install: true) }
    }

    @Test func onlyPermissionRequestBlocks() throws {
        let (installer, url) = try makeInstaller(nil)
        try installer.apply(install: true)
        let hooks = try #require(try JSONValue.parse(try Data(contentsOf: url))["hooks"])
        let blocking = try #require(hooks["PermissionRequest"]?.arrayValue?.first?["hooks"]?.arrayValue?.first)
        #expect(blocking["async"] == nil)
        #expect(blocking["timeout"] == .number(String(ClaudeHook.waitSeconds + 10)))
        let status = try #require(hooks["PreToolUse"]?.arrayValue?.first?["hooks"]?.arrayValue?.first)
        #expect(status["async"] == .bool(true))
    }

    @Test func reinstallUpgradesAnOldAsyncPermissionHook() throws {
        func entry(_ body: String) -> String {
            #"{"hooks":[{"type":"command","command":"\#(Self.hook)",\#(body)}]}"#
        }
        var sections = HookInstaller.events.filter { $0 != "PermissionRequest" }.map {
            #""\#($0)":[\#(entry(#""async":true,"timeout":10"#))]"#
        }
        sections.append(#""PermissionRequest":[\#(entry(#""async":true,"timeout":10"#))]"#)
        let (installer, url) = try makeInstaller("{\"hooks\":{\(sections.joined(separator: ","))}}")
        let (change, backup) = try installer.apply(install: true)
        #expect(change.changed == ["PermissionRequest"]) // everything else already matched
        #expect(backup != nil)
        let hooks = try #require(try JSONValue.parse(try Data(contentsOf: url))["hooks"])
        #expect(hooks["PermissionRequest"]?.arrayValue?.count == 1) // updated in place, not duplicated
        #expect(hooks["PermissionRequest"]?.arrayValue?.first?["hooks"]?.arrayValue?.first?["async"] == nil)
    }

    @Test func quotesPathsThatNeedIt() throws {
        let (installer, url) = try makeInstaller(nil, hookPath: "/Users/o'neil/My Apps/island-hook")
        try installer.apply(install: true)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains(#""command": "'/Users/o'\\''neil/My Apps/island-hook'""#))
        #expect(try installer.registeredEvents() == HookInstaller.events)
    }
}
