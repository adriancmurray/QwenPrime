import Foundation
import Testing
@testable import QwenPrime

@Suite("Native agent edit and test loop")
struct NativeAgentRuntimeEditTestLoopTests {
    @Test("An approved mutation permits rerunning the same task in one agent run")
    func rerunsTaskAfterApprovedMutation() async throws {
        let firstTest = ToolCall(
            id: "test-before-edit",
            type: "function",
            function: .init(
                name: "workspace_run_task",
                arguments: #"{"task":"swift_test","working_directory":"Fixture"}"#
            )
        )
        let patch = ToolCall(
            id: "approved-edit",
            type: "function",
            function: .init(
                name: "workspace_apply_patch",
                arguments: #"{"path":"Fixture/Sources/App.swift","old_text":"broken","new_text":"fixed"}"#
            )
        )
        let secondTest = ToolCall(
            id: "test-after-edit",
            type: "function",
            function: firstTest.function
        )
        let inference = ScriptedAgentInference(turns: [
            [.toolCall(firstTest), .finished],
            [.toolCall(patch), .finished],
            [.toolCall(secondTest), .finished],
            [.contentDelta("The edit passed the test."), .finished]
        ])
        let executor = ScriptedAgentToolExecutor()
        await executor.setCustomHandler { call in
            switch call.id {
            case firstTest.id:
                return AgentToolResult(
                    callId: call.id,
                    toolName: call.function.name,
                    content: "Tests failed.",
                    isSuccess: false
                )
            case patch.id:
                return AgentToolResult(
                    callId: call.id,
                    toolName: call.function.name,
                    content: "Applied.",
                    isSuccess: true,
                    mutationProposal: WorkspaceMutationProposal(
                        operation: .applyPatch,
                        relativePath: "Fixture/Sources/App.swift",
                        expectedContent: "broken",
                        proposedContent: "fixed",
                        preview: "-broken\n+fixed"
                    ),
                    approvalState: .approved
                )
            case secondTest.id:
                return AgentToolResult(
                    callId: call.id,
                    toolName: call.function.name,
                    content: "Tests passed.",
                    isSuccess: true
                )
            default:
                return AgentToolResult(
                    callId: call.id,
                    toolName: call.function.name,
                    content: "Unexpected call.",
                    isSuccess: false
                )
            }
        }
        let runtime = NativeAgentRuntime(inference: inference, toolExecutor: executor)

        var content = ""
        for try await event in runtime.run(
            history: [ChatMessage(role: .user, content: "Fix the failing test")],
            configuration: AgentRunConfiguration(maxTurns: 12)
        ) {
            if case .contentDelta(let delta) = event {
                content += delta
            }
        }

        #expect(content == "The edit passed the test.")
        #expect(await executor.getExecutedCalls().map(\.id) == [
            firstTest.id,
            patch.id,
            secondTest.id
        ])
    }
}
