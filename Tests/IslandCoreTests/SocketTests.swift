import Foundation
import Testing
@testable import IslandCore

/// Thread-safe box for values captured from server callbacks.
final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

func waitUntil(_ timeout: TimeInterval = 2, _ condition: @Sendable () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

/// Unix socket paths must stay under 104 bytes, so keep the name short.
func shortSocketURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("isl-\(UUID().uuidString.prefix(8)).sock")
}

func question(_ session: String = "s1") -> AgentEvent {
    AgentEvent(agent: "claude", sessionId: session, cwd: "/x", event: "PermissionRequest", tool: "Bash", message: nil,
               permission: PermissionPrompt(tool: "Bash", title: "Run command", detail: "ls", waitSeconds: 5))
}

func encoded(_ event: AgentEvent) throws -> Data {
    try AgentEvent.makeEncoder().encode(event)
}

@Suite("Socket", .serialized) struct SocketTests {
    @Test func plainEventsArriveWithoutAResponder() async throws {
        let url = shortSocketURL()
        let seen = Box<[String]>([])
        let hadResponder = Box(false)
        let server = SocketServer(url: url) { event, responder in
            if responder != nil { hadResponder.value = true }
            seen.value.append(event.event)
        }
        try server.start()
        defer { server.stop() }

        let event = AgentEvent(agent: "claude", sessionId: "s", cwd: nil, event: "Stop", tool: nil, message: nil)
        let sent = UnixSocket.send(try encoded(event), to: url)
        let arrived = await waitUntil { seen.value == ["Stop"] }
        #expect(sent)
        #expect(arrived)
        #expect(!hadResponder.value)
    }

    @Test func aQuestionGetsItsAnswer() async throws {
        let url = shortSocketURL()
        let server = SocketServer(url: url) { _, responder in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { responder?.reply(DecisionReply(.allowAlways)) }
        }
        try server.start()
        defer { server.stop() }

        let started = Date()
        let answer = UnixSocket.request(try encoded(question()), timeout: 2, to: url)
        let data = try #require(answer)
        let reply = try JSONDecoder().decode(DecisionReply.self, from: data)
        #expect(reply.decision == .allowAlways)
        #expect(Date().timeIntervalSince(started) < 1.5)
    }

    @Test func aQuestionNobodyAnswersTimesOutAndTheServerNotices() async throws {
        let url = shortSocketURL()
        let gone = Box(false)
        let server = SocketServer(url: url) { _, responder in responder?.onDisconnect = { gone.value = true } }
        try server.start()
        defer { server.stop() }

        let answer = UnixSocket.request(try encoded(question()), timeout: 0.3, to: url)
        let noticed = await waitUntil { gone.value }
        #expect(answer == nil)
        #expect(noticed)
    }

    @Test func noAppMeansAnImmediateNil() {
        let started = Date()
        let answer = UnixSocket.request(Data("{}".utf8), timeout: 5, to: shortSocketURL())
        #expect(answer == nil)
        #expect(Date().timeIntervalSince(started) < 0.5)
    }

    @Test func aStaleSocketFileMeansAnImmediateNil() {
        let url = shortSocketURL()
        FileManager.default.createFile(atPath: url.path, contents: nil) // a leftover from a crashed app
        defer { try? FileManager.default.removeItem(at: url) }
        let started = Date()
        let answer = UnixSocket.request(Data("{}".utf8), timeout: 5, to: url)
        #expect(answer == nil)
        #expect(Date().timeIntervalSince(started) < 0.5)
    }

    @Test func replyingAfterTheHookLeftIsHarmless() async throws {
        let url = shortSocketURL()
        let responders = Box<[Responder]>([])
        let gone = Box(false)
        let server = SocketServer(url: url) { _, responder in
            guard let responder else { return }
            responder.onDisconnect = { gone.value = true }
            responders.value.append(responder)
        }
        try server.start()
        defer { server.stop() }

        _ = UnixSocket.request(try encoded(question()), timeout: 0.2, to: url)
        let noticed = await waitUntil { gone.value }
        #expect(noticed)
        responders.value.first?.reply(DecisionReply(.allow)) // must neither crash (SIGPIPE) nor hang
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test func severalQuestionsAreAnsweredIndependently() async throws {
        let url = shortSocketURL()
        let server = SocketServer(url: url) { event, responder in
            // Answer according to the session, the first one later than the second.
            let decision: Decision = event.sessionId == "first" ? .allow : .deny
            let delay = event.sessionId == "first" ? 0.15 : 0.02
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { responder?.reply(DecisionReply(decision)) }
        }
        try server.start()
        defer { server.stop() }

        let firstMessage = try encoded(question("first"))
        let secondMessage = try encoded(question("second"))
        async let first = Task.detached { UnixSocket.request(firstMessage, timeout: 2, to: url) }.value
        async let second = Task.detached { UnixSocket.request(secondMessage, timeout: 2, to: url) }.value
        let firstAnswer = await first
        let secondAnswer = await second

        let decoder = JSONDecoder()
        let a = try decoder.decode(DecisionReply.self, from: try #require(firstAnswer))
        let b = try decoder.decode(DecisionReply.self, from: try #require(secondAnswer))
        #expect(a.decision == .allow)
        #expect(b.decision == .deny)
    }
}
