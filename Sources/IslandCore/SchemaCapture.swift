import Foundation

/// Learns what an agent really sends without ever writing what the user typed.
///
/// A captured payload keeps its field names, nesting and types, plus the few enum-like values that explain the
/// protocol (`hook_event_name`, `notification_type`, `tool_name`...). Every other string becomes `"<string>"` and every
/// number `"<number>"`, so prompts, commands, paths and file contents never reach the disk.
/// Off unless the file `~/.island/capture-schema` exists. Identical shapes are stored once.
public enum SchemaCapture {
    /// Values that describe the protocol rather than carry user content.
    static let safeKeys: Set<String> = [
        "hook_event_name", "notification_type", "tool_name", "source", "reason", "permission_mode",
        "behavior", "type", "destination", "mode", "toolName",
    ]

    public static func redact(_ value: JSONValue, key: String? = nil) -> JSONValue {
        switch value {
        case .string:
            return safeKeys.contains(key ?? "") ? value : .string("<string>")
        case .number:
            return .string("<number>")
        case .bool, .null:
            return value
        case .array(let items):
            return .array(items.map { redact($0, key: key) })
        case .object(let members):
            return .object(members.map { JSONMember($0.key, redact($0.value, key: $0.key)) })
        }
    }

    public static func isEnabled(in directory: URL = IslandPaths.home) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("capture-schema").path)
    }

    /// Appends the redacted payload to `schema.jsonl` unless the same shape is already there. Never throws.
    public static func captureIfEnabled(_ payload: JSONValue, in directory: URL = IslandPaths.home, now: Date = Date()) {
        guard isEnabled(in: directory) else { return }
        let shape = redact(payload).compact()
        let file = directory.appendingPathComponent("schema.jsonl")
        let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        guard existing.utf8.count < 512 * 1024, !existing.contains(shape) else { return }

        let stamp = ISO8601DateFormatter().string(from: now)
        let line = JSONValue.object([JSONMember("seen", .string(stamp)), JSONMember("payload", redact(payload))]).compact() + "\n"
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}
