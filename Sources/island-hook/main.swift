import Foundation
import IslandCore

// Agent hook (Claude Code, Codex CLI, Gemini CLI): reads the hook JSON from stdin and forwards it to the app.
//
// Golden rule: never break the agent. Every failure path prints nothing and exits 0, which for a
// PermissionRequest hook means "no decision", so Claude Code asks in the terminal as if we were not here.

signal(SIGPIPE, SIG_IGN)

let input = FileHandle.standardInput.readDataToEndOfFile()

// Debug aid: ISLAND_DUMP=/path/file.jsonl appends every raw payload, to see what an agent really sends.
if let path = ProcessInfo.processInfo.environment["ISLAND_DUMP"] {
    if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(input + Data("\n".utf8))
        try? handle.close()
    }
}

guard let payload = try? JSONValue.parse(input), case .object = payload else { exit(0) }

// Opt-in (touch ~/.island/capture-schema): records the shape of each payload, never its content.
SchemaCapture.captureIfEnabled(payload)

// ISLAND_WAIT=<seconds> shortens the wait, for testing.
let wait = ProcessInfo.processInfo.environment["ISLAND_WAIT"].flatMap(Int.init) ?? ClaudeHook.waitSeconds
// `island-hook --agent codex|gemini` says who is calling (no argument: Claude Code).
let agent = AgentKind(arguments: CommandLine.arguments) ?? .claude
let event = agent == .gemini
    ? GeminiHook.event(from: payload, parentPid: Int(getppid()))
    : ClaudeHook.event(from: payload, parentPid: Int(getppid()), waitSeconds: wait, agent: agent)
guard let message = try? AgentEvent.makeEncoder().encode(event) else { exit(0) }

if let prompt = event.permission {
    // Blocks until you answer in the island, it gives up, or the app is not running.
    if let answer = UnixSocket.request(message, timeout: TimeInterval(prompt.waitSeconds)),
       let reply = try? JSONDecoder().decode(DecisionReply.self, from: answer),
       let output = ClaudeHook.stdout(for: reply.decision, payload: payload) {
        print(output)
    }
    exit(0)
}

UnixSocket.send(message)
exit(0)
