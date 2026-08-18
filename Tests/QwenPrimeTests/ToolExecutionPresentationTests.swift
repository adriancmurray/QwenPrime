import Testing
@testable import QwenPrime

@Suite("Tool Execution Presentation Tests")
struct ToolExecutionPresentationTests {
    @Test("Consecutive successful workspace reads collapse into one ordered group")
    func groupsConsecutiveWorkspaceReads() throws {
        let instructions = ToolExecution(
            id: "instructions",
            toolName: "instructions__AGENTS.md",
            input: "AGENTS.md",
            isSuccess: true
        )
        let firstRead = ToolExecution(
            id: "read-1",
            toolName: "workspace_list_directory",
            input: "{}",
            isSuccess: true
        )
        let secondRead = ToolExecution(
            id: "read-2",
            toolName: "workspace_read_file",
            input: #"{"path":"Package.swift"}"#,
            isSuccess: true
        )

        let items = ToolExecutionPresentation.items(
            for: [instructions, firstRead, secondRead]
        )

        #expect(items.count == 2)
        guard case .execution(let presentedInstructions) = items[0] else {
            Issue.record("Expected workspace instructions to remain individually visible")
            return
        }
        #expect(presentedInstructions.id == "instructions")

        guard case .workspaceReadGroup(let reads) = items[1] else {
            Issue.record("Expected adjacent workspace reads to collapse")
            return
        }
        #expect(reads.map(\.id) == ["read-1", "read-2"])
    }

    @Test("Failures and consequential tools always remain individually visible")
    func preservesFailuresAndConsequentialTools() {
        let failedRead = ToolExecution(
            id: "failed-read",
            toolName: "workspace_read_file",
            input: "{}",
            isSuccess: false
        )
        let mutation = ToolExecution(
            id: "mutation",
            toolName: "workspace_write_file",
            input: "{}",
            isSuccess: true
        )
        let mcp = ToolExecution(
            id: "mcp",
            toolName: "mcp__local__add_numbers",
            input: "{}",
            isSuccess: true
        )

        let items = ToolExecutionPresentation.items(for: [failedRead, mutation, mcp])

        #expect(items.count == 3)
        #expect(items.allSatisfy { item in
            if case .execution = item { return true }
            return false
        })
    }

    @Test("A single workspace read is not wrapped in a group")
    func leavesSingleReadAlone() {
        let read = ToolExecution(
            id: "read",
            toolName: "workspace_search_text",
            input: "{}",
            isRunning: true
        )

        let items = ToolExecutionPresentation.items(for: [read])

        #expect(items == [.execution(read)])
    }
}
