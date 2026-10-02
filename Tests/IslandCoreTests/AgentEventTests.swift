import Foundation
import Testing
@testable import IslandCore

@Suite("AgentEvent") struct AgentEventTests {
    @Test func wireFormatKeepsSubSecondOrder() throws {
        let first = AgentEvent(agent: "claude", sessionId: "s", cwd: "/x", event: "PostToolUse", tool: "Bash", message: nil,
                               pid: 42, timestamp: Date(timeIntervalSince1970: 1_000.250))
        let second = AgentEvent(agent: "claude", sessionId: "s", cwd: "/x", event: "Stop", tool: nil, message: nil,
                                timestamp: Date(timeIntervalSince1970: 1_000.750))
        let decoder = AgentEvent.makeDecoder()
        let a = try decoder.decode(AgentEvent.self, from: AgentEvent.makeEncoder().encode(first))
        let b = try decoder.decode(AgentEvent.self, from: AgentEvent.makeEncoder().encode(second))
        #expect(a.timestamp < b.timestamp) // with whole seconds these two would tie
        #expect(a.pid == 42)
        #expect(b.pid == nil)
    }
}
