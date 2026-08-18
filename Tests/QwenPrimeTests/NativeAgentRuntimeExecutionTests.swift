import Testing
import Foundation
@testable import QwenPrime

@Suite("NativeAgentRuntime Execution Tests")
struct NativeAgentRuntimeExecutionTests {

    @Test("Content from a tool-request turn is not emitted as final answer text")
    func testToolTurnContentIsProvisional() async throws {
        let call = ToolCall(
            id: "call-provisional",
            type: "function",
            function: .init(name: "workspace_write_file", arguments: "{}")
        )
        let inference = ScriptedAgentInference(turns: [
            [
                .contentDelta("Premature answer before the tool result."),
                .toolCall(call),
                .finished
            ],
            [
                .contentDelta("Final answer after the tool result."),
                .finished
            ]
        ])
        let executor = ScriptedAgentToolExecutor()
        await executor.registerResult(
            AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Rejected by user.",
                isSuccess: false,
                approvalState: .rejected
            ),
            forCallId: call.id
        )
        let runtime = NativeAgentRuntime(inference: inference, toolExecutor: executor)

        var events: [AgentEvent] = []
        var projection = AgentMessageProjection(
            message: ChatMessage(role: .assistant, content: "", isStreaming: true)
        )
        for try await event in runtime.run(history: [ChatMessage(role: .user, content: "change")]) {
            events.append(event)
            projection.apply(event)
        }

        #expect(events.contains(.contentReset("")))
        #expect(projection.message.content == "Final answer after the tool result.")
    }

    @Test("Direct final response: one model turn forwards reasoning, content, usage, emits finished once, executes no tools, and preserves order")
    func testDirectFinalResponseOneTurn() async throws {
        let stats = AgentLoopTestHelpers.sampleStats()
        let inference = ScriptedAgentInference(turns: [
            [
                .reasoningDelta("I should greet the user directly."),
                .contentDelta("Hello! "),
                .contentDelta("How can I assist you with the workspace today?"),
                .usage(stats),
                .finished
            ]
        ])

        let toolExecutor = ScriptedAgentToolExecutor(tools: [
            AgentLoopTestHelpers.sampleWorkspaceListTool()
        ])

        let runtime = NativeAgentRuntime(
            inference: inference,
            toolExecutor: toolExecutor
        )

        let initialHistory = [
            ChatMessage(role: .user, content: "Hello")
        ]

        let config = AgentRunConfiguration(
            systemPrompt: "You are a helpful assistant.",
            maxTurns: 5
        )

        var receivedEvents: [AgentEvent] = []
        let stream = runtime.run(
            history: initialHistory,
            configuration: config
        )

        for try await event in stream {
            receivedEvents.append(event)
        }

        // Verify event sequence and ordering
        #expect(receivedEvents.count == 5)
        if receivedEvents.count >= 5 {
            #expect(receivedEvents[0] == .reasoningDelta("I should greet the user directly."))
            #expect(receivedEvents[1] == .contentDelta("Hello! "))
            #expect(receivedEvents[2] == .contentDelta("How can I assist you with the workspace today?"))
            #expect(receivedEvents[3] == .usage(stats))
            #expect(receivedEvents[4] == .finished)
        }

        // Verify finished event emitted exactly once
        let finishedCount = receivedEvents.filter { $0 == .finished }.count
        #expect(finishedCount == 1)

        // Verify no tool was executed
        let executedCalls = await toolExecutor.getExecutedCalls()
        #expect(executedCalls.isEmpty)

        // Verify inference was called with initial transcript including user message
        let transcripts = await inference.getCapturedTranscripts()
        #expect(transcripts.count == 1)
        if let firstTranscript = transcripts.first {
            #expect(firstTranscript.count == 1)
            #expect(firstTranscript.first?.role == .user)
            #expect(firstTranscript.first?.content == "Hello")
        }
    }

    @Test("One tool round: turn 1 emits toolCall, runtime emits lifecycle events, executes tool, appends tool response to transcript, runs turn 2 and finishes")
    func testSingleToolRoundExecutionAndTranscriptProgression() async throws {
        let toolCall = ToolCall(
            id: "call_dir_1",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "workspace_list_directory",
                arguments: "{\"path\":\"Sources\"}"
            )
        )

        let inference = ScriptedAgentInference(turns: [
            // Turn 1: Model decides to call a tool
            [
                .reasoningDelta("I need to check the files in Sources."),
                .toolCall(toolCall),
                .finished
            ],
            // Turn 2: Model receives tool result and provides final answer
            [
                .contentDelta("The Sources directory contains App, Models, Services, Theme, ViewModels, and Views."),
                .finished
            ]
        ])

        let toolExecutor = ScriptedAgentToolExecutor(tools: [
            AgentLoopTestHelpers.sampleWorkspaceListTool()
        ])
        await toolExecutor.registerResult(
            AgentToolResult(
                callId: "call_dir_1",
                toolName: "workspace_list_directory",
                content: "[\"App\",\"Models\",\"Services\",\"Theme\",\"ViewModels\",\"Views\"]",
                isSuccess: true
            ),
            forCallId: "call_dir_1"
        )

        let runtime = NativeAgentRuntime(
            inference: inference,
            toolExecutor: toolExecutor
        )

        let history = [
            ChatMessage(role: .user, content: "List Sources")
        ]

        var receivedEvents: [AgentEvent] = []
        let stream = runtime.run(
            history: history,
            configuration: AgentRunConfiguration(maxTurns: 5)
        )

        for try await event in stream {
            receivedEvents.append(event)
        }

        // Verify tool lifecycle events were emitted
        let hasToolRequested = receivedEvents.contains { event in
            if case .toolRequested(let call) = event {
                return call.id == "call_dir_1" && call.function.name == "workspace_list_directory"
            }
            return false
        }
        #expect(hasToolRequested)

        let hasToolStarted = receivedEvents.contains { event in
            if case .toolStarted(let callId, let toolName) = event {
                return callId == "call_dir_1" && toolName == "workspace_list_directory"
            }
            return false
        }
        #expect(hasToolStarted)

        let hasToolCompleted = receivedEvents.contains { event in
            if case .toolCompleted(let result) = event {
                return result.callId == "call_dir_1" && result.isSuccess
            }
            return false
        }
        #expect(hasToolCompleted)

        // Verify final content delta and single finished
        let contentDeltas = receivedEvents.compactMap { event -> String? in
            if case .contentDelta(let text) = event { return text }
            return nil
        }
        #expect(contentDeltas.joined().contains("The Sources directory contains"))
        #expect(receivedEvents.last == .finished)

        // Verify tool executor was called exactly once
        let executedCalls = await toolExecutor.getExecutedCalls()
        #expect(executedCalls.count == 1)
        #expect(executedCalls.first?.id == "call_dir_1")

        // Verify Turn 2 inference transcript received assistant tool_calls + matching role=tool response
        let transcripts = await inference.getCapturedTranscripts()
        #expect(transcripts.count == 2)
        if transcripts.count >= 2 {
            let turn2Messages = transcripts[1]
            #expect(turn2Messages.count == 3) // user, assistant (with tool_calls), tool
            if turn2Messages.count >= 3 {
                #expect(turn2Messages[0].role == .user)
                #expect(turn2Messages[1].role == .assistant)
                #expect(turn2Messages[1].toolCalls?.first?.id == "call_dir_1")
                #expect(turn2Messages[1].reasoningContent == "I need to check the files in Sources.")
                #expect(turn2Messages[2].role == .tool)
                #expect(turn2Messages[2].toolCallId == "call_dir_1")
                #expect(turn2Messages[2].content == "[\"App\",\"Models\",\"Services\",\"Theme\",\"ViewModels\",\"Views\"]")
            }
        }
    }

    @Test("Tool failures are appended as role=tool responses and returned to the model for correction without crashing")
    func testToolFailureAppendedAsToolResponseForCorrection() async throws {
        let failedCall = ToolCall(
            id: "call_read_err",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "workspace_read_file",
                arguments: "{\"path\":\"NonExistent.swift\"}"
            )
        )

        let inference = ScriptedAgentInference(turns: [
            // Turn 1: Model calls tool for non-existent file
            [
                .toolCall(failedCall),
                .finished
            ],
            // Turn 2: Model receives failure and replies to user
            [
                .contentDelta("The requested file NonExistent.swift could not be found."),
                .finished
            ]
        ])

        let toolExecutor = ScriptedAgentToolExecutor(tools: [
            AgentLoopTestHelpers.sampleWorkspaceReadTool()
        ])
        await toolExecutor.registerResult(
            AgentToolResult(
                callId: "call_read_err",
                toolName: "workspace_read_file",
                content: "File not found: NonExistent.swift",
                isSuccess: false
            ),
            forCallId: "call_read_err"
        )

        let runtime = NativeAgentRuntime(
            inference: inference,
            toolExecutor: toolExecutor
        )

        var receivedEvents: [AgentEvent] = []
        let stream = runtime.run(
            history: [ChatMessage(role: .user, content: "Read NonExistent.swift")],
            configuration: AgentRunConfiguration(maxTurns: 5)
        )

        for try await event in stream {
            receivedEvents.append(event)
        }

        // Verify tool completed event carried isSuccess: false
        let completedEvent = receivedEvents.first { event in
            if case .toolCompleted(let result) = event {
                return result.callId == "call_read_err"
            }
            return false
        }
        guard case .toolCompleted(let result) = completedEvent else {
            Issue.record("Expected toolCompleted event")
            return
        }
        #expect(result.isSuccess == false)
        #expect(result.content.contains("File not found"))

        // Verify Turn 2 transcript got role=tool failure content
        let transcripts = await inference.getCapturedTranscripts()
        #expect(transcripts.count == 2)
        if transcripts.count >= 2 {
            let turn2Messages = transcripts[1]
            guard let toolMsg = turn2Messages.last else {
                Issue.record("Expected tool message in turn 2 transcript")
                return
            }
            #expect(toolMsg.role == .tool)
            #expect(toolMsg.toolCallId == "call_read_err")
            #expect(toolMsg.content == "File not found: NonExistent.swift")
        }
    }

    @Test("Multiple tool calls in one turn execute sequentially in stable index order and all results are included before next model turn")
    func testMultipleToolCallsInOneTurnExecuteSequentiallyInIndexOrder() async throws {
        let call1 = ToolCall(
            id: "call_seq_1",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "workspace_list_directory",
                arguments: "{\"path\":\"Sources\"}"
            )
        )
        let call2 = ToolCall(
            id: "call_seq_2",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "workspace_read_file",
                arguments: "{\"path\":\"Package.swift\"}"
            )
        )

        let inference = ScriptedAgentInference(turns: [
            // Turn 1: Model emits two tool calls in one turn
            [
                .toolCall(call1),
                .toolCall(call2),
                .finished
            ],
            // Turn 2: Final response
            [
                .contentDelta("Inspected both directory and Package.swift."),
                .finished
            ]
        ])

        let toolExecutor = ScriptedAgentToolExecutor(tools: [
            AgentLoopTestHelpers.sampleWorkspaceListTool(),
            AgentLoopTestHelpers.sampleWorkspaceReadTool()
        ])
        await toolExecutor.registerResult(
            AgentToolResult(callId: "call_seq_1", toolName: "workspace_list_directory", content: "[\"Sources\"]", isSuccess: true),
            forCallId: "call_seq_1"
        )
        await toolExecutor.registerResult(
            AgentToolResult(callId: "call_seq_2", toolName: "workspace_read_file", content: "// swift-tools-version: 6.0", isSuccess: true),
            forCallId: "call_seq_2"
        )

        let runtime = NativeAgentRuntime(
            inference: inference,
            toolExecutor: toolExecutor
        )

        var receivedEvents: [AgentEvent] = []
        let stream = runtime.run(
            history: [ChatMessage(role: .user, content: "Check workspace")],
            configuration: AgentRunConfiguration(maxTurns: 5)
        )

        for try await event in stream {
            receivedEvents.append(event)
        }

        // Verify tool execution order on tool executor
        let executedCalls = await toolExecutor.getExecutedCalls()
        #expect(executedCalls.count == 2)
        if executedCalls.count >= 2 {
            #expect(executedCalls[0].id == "call_seq_1")
            #expect(executedCalls[1].id == "call_seq_2")
        }

        // Verify Turn 2 transcript has assistant message with both tool_calls, followed by both tool responses
        let transcripts = await inference.getCapturedTranscripts()
        #expect(transcripts.count == 2)
        if transcripts.count >= 2 {
            let turn2Messages = transcripts[1]
            #expect(turn2Messages.count == 4) // user, assistant (2 calls), tool 1, tool 2
            if turn2Messages.count >= 4 {
                #expect(turn2Messages[1].role == .assistant)
                #expect(turn2Messages[1].toolCalls?.count == 2)
                #expect(turn2Messages[1].toolCalls?[0].id == "call_seq_1")
                #expect(turn2Messages[1].toolCalls?[1].id == "call_seq_2")

                #expect(turn2Messages[2].role == .tool)
                #expect(turn2Messages[2].toolCallId == "call_seq_1")
                #expect(turn2Messages[2].content == "[\"Sources\"]")

                #expect(turn2Messages[3].role == .tool)
                #expect(turn2Messages[3].toolCallId == "call_seq_2")
                #expect(turn2Messages[3].content == "// swift-tools-version: 6.0")
            }
        }
    }

    @Test("Unknown or malformed tool calls are handled through tool executor structured failure without shell fallback")
    func testUnknownToolCallHandledThroughStructuredFailure() async throws {
        let unknownCall = ToolCall(
            id: "call_unk_1",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "shell_exec",
                arguments: "{\"cmd\":\"ls -la\"}"
            )
        )

        let inference = ScriptedAgentInference(turns: [
            // Turn 1: Model requests arbitrary shell tool
            [
                .toolCall(unknownCall),
                .finished
            ],
            // Turn 2: Model recovers from unknown tool error
            [
                .contentDelta("I cannot run arbitrary shell commands; I only have workspace read tools."),
                .finished
            ]
        ])

        let toolExecutor = ScriptedAgentToolExecutor(tools: [
            AgentLoopTestHelpers.sampleWorkspaceListTool()
        ])

        let runtime = NativeAgentRuntime(
            inference: inference,
            toolExecutor: toolExecutor
        )

        var receivedEvents: [AgentEvent] = []
        let stream = runtime.run(
            history: [ChatMessage(role: .user, content: "Run shell")],
            configuration: AgentRunConfiguration(maxTurns: 5)
        )

        for try await event in stream {
            receivedEvents.append(event)
        }

        // Verify structured failure was passed back to model
        let transcripts = await inference.getCapturedTranscripts()
        #expect(transcripts.count == 2)
        if transcripts.count >= 2 {
            let turn2Messages = transcripts[1]
            guard let lastMsg = turn2Messages.last else {
                Issue.record("Expected last message in transcript")
                return
            }
            #expect(lastMsg.role == .tool)
            #expect(lastMsg.toolCallId == "call_unk_1")
            #expect(lastMsg.content?.contains("Unknown tool") == true)
        }
    }

    @Test("Executor result with mismatched callId or toolName is normalized to requested ToolCall id and name before events and transcript")
    func testExecutorResultWithMismatchedIdOrNameIsNormalized() async throws {
        let requestedCall = ToolCall(
            id: "call_req_exact_42",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "workspace_read_file",
                arguments: "{\"path\":\"README.md\"}"
            )
        )

        let inference = ScriptedAgentInference(turns: [
            // Turn 1: Model requests tool with id call_req_exact_42
            [
                .toolCall(requestedCall),
                .finished
            ],
            // Turn 2: Final response
            [
                .contentDelta("Read README successfully."),
                .finished
            ]
        ])

        let toolExecutor = ScriptedAgentToolExecutor(tools: [
            AgentLoopTestHelpers.sampleWorkspaceReadTool()
        ])
        // Handler returns mismatched callId and toolName
        await toolExecutor.setCustomHandler { _ in
            AgentToolResult(
                callId: "mismatched_executor_id_999",
                toolName: "mismatched_executor_tool",
                content: "# Project Readme",
                isSuccess: true
            )
        }

        let runtime = NativeAgentRuntime(
            inference: inference,
            toolExecutor: toolExecutor
        )

        var receivedEvents: [AgentEvent] = []
        let stream = runtime.run(
            history: [ChatMessage(role: .user, content: "Read README")],
            configuration: AgentRunConfiguration(maxTurns: 5)
        )

        for try await event in stream {
            receivedEvents.append(event)
        }

        // 1. Verify toolCompleted event is normalized to requested callId and toolName
        let completedEvent = receivedEvents.first { event in
            if case .toolCompleted = event { return true }
            return false
        }

        guard case .toolCompleted(let result) = completedEvent else {
            Issue.record("Expected toolCompleted event")
            return
        }

        #expect(result.callId == "call_req_exact_42")
        #expect(result.toolName == "workspace_read_file")
        #expect(result.content == "# Project Readme")
        #expect(result.isSuccess == true)

        // 2. Verify Turn 2 transcript received normalized toolCallId
        let transcripts = await inference.getCapturedTranscripts()
        #expect(transcripts.count == 2)
        if transcripts.count >= 2 {
            let turn2Messages = transcripts[1]
            guard let toolMsg = turn2Messages.last(where: { $0.role == .tool }) else {
                Issue.record("Expected tool response message in turn 2 transcript")
                return
            }
            #expect(toolMsg.toolCallId == "call_req_exact_42")
            #expect(toolMsg.content == "# Project Readme")
        }
    }
}
