import Testing
@testable import IslandCore

@Suite("Tool names") struct ToolNameTests {
    @Test func mcpToolsShowOnlyTheTool() {
        #expect(ToolName.display("mcp__4380726e-b365-47b2-8034-d111417648ac__search_threads") == "search_threads")
        #expect(ToolName.display("mcp__github__create_issue") == "create_issue")
    }

    @Test func ordinaryToolsAreUntouched() {
        #expect(ToolName.display("Bash") == "Bash")
        #expect(ToolName.display("mcp__") == "mcp__")
        #expect(ToolName.display("mcp__onlyserver") == "mcp__onlyserver")
    }

    @Test func everythingIsBounded() {
        let long = String(repeating: "x", count: 200)
        #expect(ToolName.display(long).count == ToolName.maxLength)
        #expect(ToolName.display("mcp__s__" + long).count == ToolName.maxLength)
        #expect(ToolName.clipped("short", to: 10) == "short")
        #expect(ToolName.clipped("abcdefghij", to: 5) == "abcd…")
    }
}
