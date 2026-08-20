import Testing
@testable import QwenPrime

@Suite("Tool Execution Presentation Tests")
struct ToolExecutionPresentationTests {
    @Test("Consecutive successful workspace reads collapse into one ordered group")
    func groupsConsecutiveWorkspaceReads() throws {
        let instructions = ToolExecution(
            id: "instructions",
            toolName: ToolName.workspaceInstructions,
            input: "AGENTS.md",
            isSuccess: true
        )
        let firstRead = ToolExecution(
            id: "read-1",
            toolName: ToolName.workspaceListDirectory,
            input: "{}",
            isSuccess: true
        )
        let secondRead = ToolExecution(
            id: "read-2",
            toolName: ToolName.workspaceReadFile,
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
            toolName: ToolName.workspaceReadFile,
            input: "{}",
            isSuccess: false
        )
        let mutation = ToolExecution(
            id: "mutation",
            toolName: ToolName.workspaceWriteFile,
            input: "{}",
            isSuccess: true
        )
        let mcp = ToolExecution(
            id: "mcp",
            toolName: ToolName.mcp(provider: "local", tool: "add_numbers"),
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
            toolName: ToolName.workspaceSearchText,
            input: "{}",
            isRunning: true
        )

        let items = ToolExecutionPresentation.items(for: [read])

        #expect(items == [.execution(read)])
    }

    @Test("Every workspace mutation is presented as a workspace change")
    func categorizesEveryWorkspaceMutation() {
        let categories = ToolName.workspaceMutationTools.map {
            ToolExecutionCategory(toolName: $0)
        }

        #expect(categories.count == 3)
        #expect(categories.allSatisfy { $0 == .workspaceChange })
        #expect(categories.allSatisfy { $0.label == "Workspace Change" })
    }

    @Test("Canonical tool contracts drive category resolution")
    func canonicalToolContractsDriveCategories() {
        let workspaceReads = ToolName.workspaceReadTools

        #expect(
            workspaceReads.allSatisfy {
                ToolExecutionCategory(toolName: $0) == .workspaceRead
            }
        )
        #expect(
            ToolExecutionCategory(toolName: ToolName.workspaceProcessStatus)
                == .workspaceProcess
        )
        let reversedWorkspaceChecks: [(Bool, ToolExecutionCategory)] = [
            (
                ToolName.workspaceReadTools.contains(
                    ToolName.workspaceProcessStatus
                ),
                .workspaceRead
            ),
            (
                ToolNamespace.workspaceProcess.contains(
                    ToolName.workspaceProcessStatus
                ),
                .workspaceProcess
            ),
        ]
        #expect(
            reversedWorkspaceChecks.first(where: { $0.0 })?.1
                == .workspaceProcess
        )
        #expect(
            ToolExecutionCategory(
                toolName: ToolName.mcp(provider: "docs", tool: "search")
            ) == .mcpTool
        )
        #expect(
            ToolExecutionCategory(toolName: "workspace_unknown") == .tool
        )
    }

    @Test("Floating approvals use the canonical tool category icon")
    func floatingApprovalUsesCanonicalCategoryIcon() {
        let cases: [(toolName: String, expectedImage: String)] = [
            (ToolName.workspaceWriteFile, "pencil.and.list.clipboard"),
            (
                ToolName.workspaceProcessRun,
                "chevron.left.forwardslash.chevron.right"
            ),
            (
                ToolName.mcp(provider: "local", tool: "add_numbers"),
                "network"
            ),
            (ToolName.workspaceReadFile, "doc.text.magnifyingglass"),
        ]

        for testCase in cases {
            #expect(
                FloatingToolApprovalPresentation.systemImage(
                    for: testCase.toolName
                ) == testCase.expectedImage
            )
        }
    }
}
