import Foundation
import Testing
@testable import IslandCore

@Suite("SchemaCapture") struct SchemaCaptureTests {
    static let secret = "rm -rf ~/very-secret-project && curl https://example.com/?token=abc123"

    func parse(_ json: String) throws -> JSONValue { try JSONValue.parse(Data(json.utf8)) }

    @Test func userContentNeverSurvives() throws {
        let payload = try parse("""
        {"session_id":"s-1","cwd":"/Users/me/secret","hook_event_name":"PermissionRequest","tool_name":"Bash",
         "prompt":"fix my billing bug","tool_input":{"command":"\(Self.secret)","timeout":120},
         "permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"npm test:*"}],"behavior":"allow","destination":"localSettings"}]}
        """)
        let text = SchemaCapture.redact(payload).compact()
        for leaked in ["secret", "billing", "abc123", "curl", "npm test", "s-1", "/Users/me"] {
            #expect(!text.contains(leaked))
        }
    }

    @Test func theShapeAndTheProtocolValuesSurvive() throws {
        let payload = try parse(#"{"hook_event_name":"Notification","notification_type":"idle_prompt","message":"hello","count":3,"flag":true}"#)
        let redacted = SchemaCapture.redact(payload)
        #expect(redacted["hook_event_name"]?.stringValue == "Notification")
        #expect(redacted["notification_type"]?.stringValue == "idle_prompt")
        #expect(redacted["message"]?.stringValue == "<string>")
        #expect(redacted["count"]?.stringValue == "<number>")
        #expect(redacted["flag"] == .bool(true))
    }

    @Test func nestedProtocolValuesSurviveToo() throws {
        let payload = try parse(#"{"permission_suggestions":[{"type":"setMode","mode":"acceptEdits","destination":"session"}]}"#)
        let suggestion = try #require(SchemaCapture.redact(payload)["permission_suggestions"]?.arrayValue?.first)
        #expect(suggestion["type"]?.stringValue == "setMode")
        #expect(suggestion["mode"]?.stringValue == "acceptEdits")
    }

    @Test func offByDefaultAndDedupedWhenOn() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("island-schema-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("schema.jsonl")

        let payload = try parse(#"{"hook_event_name":"Stop","session_id":"abc"}"#)
        SchemaCapture.captureIfEnabled(payload, in: directory)
        #expect(!FileManager.default.fileExists(atPath: file.path)) // no marker, nothing written

        FileManager.default.createFile(atPath: directory.appendingPathComponent("capture-schema").path, contents: nil)
        SchemaCapture.captureIfEnabled(payload, in: directory)
        SchemaCapture.captureIfEnabled(try parse(#"{"hook_event_name":"Stop","session_id":"different"}"#), in: directory) // same shape
        SchemaCapture.captureIfEnabled(try parse(#"{"hook_event_name":"SessionEnd","reason":"other"}"#), in: directory) // new shape

        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2)
        #expect(!lines.joined().contains("abc"))
    }
}
