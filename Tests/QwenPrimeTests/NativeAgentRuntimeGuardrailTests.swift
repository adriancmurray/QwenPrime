import Testing
import Foundation
@testable import QwenPrime

@Suite("NativeAgentRuntime Guardrail & Concurrency Tests")
struct NativeAgentRuntimeGuardrailTests {

    @Test("Statelessness: NativeAgentRuntime stores no mutable global state; two concurrent runs proceed independently")
    func testConcurrentRunsProceedIndependentlyWithoutSharedState() async throws {
        let stats = AgentLoopTestHelpers.sampleStats()

        // Use a transcript-aware handler so responses are routed by the user message in each run's transcript
        let inference = ScriptedAgentInference { messages, _, _ in
            let lastUserContent = messages.last(where: { $0.role == .user })?.content ?? ""
            if lastUserContent.contains("Message A") {
                return [
                    .contentDelta("Response for Run A"),
                    .usage(stats),
                    .finished
                ]
            } else if lastUserContent.contains("Message B") {
                return [
                    .contentDelta("Response for Run B"),
                    .usage(stats),
                    .finished
                ]
            } else {
                return [
                    .contentDelta("Unexpected message: \(lastUserContent)"),
                    .finished
                ]
            }
        }

        let runtime = NativeAgentRuntime(
            inference: inference,
            toolExecutor: nil
        )

        let runA = Task {
            var events: [AgentEvent] = []
            let stream = runtime.run(
                history: [ChatMessage(role: .user, content: "Message A")],
                configuration: AgentRunConfiguration(maxTurns: 3)
            )
            for try await event in stream {
                events.append(event)
            }
            return events
        }

        let runB = Task {
            var events: [AgentEvent] = []
            let stream = runtime.run(
                history: [ChatMessage(role: .user, content: "Message B")],
                configuration: AgentRunConfiguration(maxTurns: 3)
            )
            for try await event in stream {
                events.append(event)
            }
            return events
        }

        let eventsA = try await runA.value
        let eventsB = try await runB.value

        let textA = eventsA.compactMap { if case .contentDelta(let t) = $0 { return t } else { return nil } }.joined()
        let textB = eventsB.compactMap { if case .contentDelta(let t) = $0 { return t } else { return nil } }.joined()

        #expect(textA.contains("Response for Run A"))
        #expect(textB.contains("Response for Run B"))

        let transcripts = await inference.getCapturedTranscripts()
        #expect(transcripts.count == 2)
    }

    @Test("Max turns guardrail: repeated tool-only turns terminate with typed maxTurnsExceeded error rather than hanging")
    func testMaxTurnsExceededTerminatesWithTypedError() async throws {
        // Provide 10 turns of unique tool calls with distinct call IDs and arguments
        // so that maxTurns is tested without triggering the duplicateToolCall guardrail.
        let repeatedTurns: [[StreamEvent]] = (0..<10).map { index in
            let call = ToolCall(
                id: "call_loop_\(index)",
                type: "function",
                function: ToolCall.FunctionCall(
                    name: "workspace_list_directory",
                    arguments: "{\"path\":\"dir_\(index)\"}"
                )
            )
            return [.toolCall(call), .finished]
        }

        let inference = ScriptedAgentInference(turns: repeatedTurns)
        let toolExecutor = ScriptedAgentToolExecutor(tools: [
            AgentLoopTestHelpers.sampleWorkspaceListTool()
        ])
        await toolExecutor.registerResult(
            AgentToolResult(callId: "", toolName: "workspace_list_directory", content: "[]", isSuccess: true),
            forToolName: "workspace_list_directory"
        )

        let runtime = NativeAgentRuntime(
            inference: inference,
            toolExecutor: toolExecutor
        )

        let maxTurnsLimit = 3
        let config = AgentRunConfiguration(maxTurns: maxTurnsLimit)

        var receivedEvents: [AgentEvent] = []
        var caughtError: (any Error)?

        do {
            let stream = runtime.run(
                history: [ChatMessage(role: .user, content: "Keep looping")],
                configuration: config
            )
            for try await event in stream {
                receivedEvents.append(event)
            }
        } catch {
            caughtError = error
        }

        guard let runtimeError = caughtError as? AgentRuntimeError else {
            Issue.record("Expected AgentRuntimeError, got: \(String(describing: caughtError))")
            return
        }

        #expect(runtimeError == .maxTurnsExceeded(limit: maxTurnsLimit))

        // Ensure finished was NOT emitted
        #expect(!receivedEvents.contains(.finished))

        // Tool executor was executed exactly maxTurnsLimit times before termination
        let executedCalls = await toolExecutor.getExecutedCalls()
        #expect(executedCalls.count == maxTurnsLimit)
    }

    @Test("Default configuration sets maxTurns to 5")
    func testDefaultConfigurationMaxTurns() {
        let defaultConfig = AgentRunConfiguration()
        #expect(defaultConfig.maxTurns == 5)
    }

    @Test("Duplicate tool call guardrail: identical name+arguments repeated in one run terminates with typed duplicateToolCall error before second execution")
    func testDuplicateToolCallInvocationTerminatesBeforeSecondExecution() async throws {
        let call1 = ToolCall(
            id: "call_1st_unique_id",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "workspace_read_file",
                arguments: "{\"path\":\"Package.swift\"}"
            )
        )
        let call2WithDifferentId = ToolCall(
            id: "call_2nd_different_id",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "workspace_read_file",
                arguments: "{\"path\":\"Package.swift\"}" // Exactly the same name & arguments!
            )
        )

        let inference = ScriptedAgentInference(turns: [
            // Turn 1: Calls Package.swift
            [
                .toolCall(call1),
                .finished
            ],
            // Turn 2: Emits identical tool call with different ID
            [
                .toolCall(call2WithDifferentId),
                .finished
            ]
        ])

        let toolExecutor = ScriptedAgentToolExecutor(tools: [
            AgentLoopTestHelpers.sampleWorkspaceReadTool()
        ])
        await toolExecutor.registerResult(
            AgentToolResult(callId: "call_1st_unique_id", toolName: "workspace_read_file", content: "// package content", isSuccess: true),
            forCallId: "call_1st_unique_id"
        )

        let runtime = NativeAgentRuntime(
            inference: inference,
            toolExecutor: toolExecutor
        )

        var caughtError: (any Error)?

        do {
            let stream = runtime.run(
                history: [ChatMessage(role: .user, content: "Read Package twice")],
                configuration: AgentRunConfiguration(maxTurns: 5)
            )
            for try await _ in stream {}
        } catch {
            caughtError = error
        }

        guard let runtimeError = caughtError as? AgentRuntimeError else {
            Issue.record("Expected AgentRuntimeError, got: \(String(describing: caughtError))")
            return
        }

        #expect(runtimeError == .duplicateToolCall(toolName: "workspace_read_file", arguments: "{\"path\":\"Package.swift\"}"))

        // Tool executor was executed only once (for call 1), never for the duplicate call 2
        let executedCalls = await toolExecutor.getExecutedCalls()
        #expect(executedCalls.count == 1)
        #expect(executedCalls.first?.id == "call_1st_unique_id")
    }

    @Test("Duplicate tool call guardrail: JSON argument whitespace and formatting variations are canonicalized as identical duplicates")
    func testDuplicateToolCallGuardrailCanonicalizesJSONWhitespaceAndFormatting() async throws {
        let call1 = ToolCall(
            id: "call_ws_1",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "workspace_read_file",
                arguments: "{\"path\":\"Package.swift\"}"
            )
        )
        let call2WhitespaceVariant = ToolCall(
            id: "call_ws_2",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "workspace_read_file",
                arguments: "{\n  \"path\":  \"Package.swift\" \n}"
            )
        )

        let inference = ScriptedAgentInference(turns: [
            [.toolCall(call1), .finished],
            [.toolCall(call2WhitespaceVariant), .finished]
        ])

        let toolExecutor = ScriptedAgentToolExecutor(tools: [
            AgentLoopTestHelpers.sampleWorkspaceReadTool()
        ])
        await toolExecutor.registerResult(
            AgentToolResult(callId: "call_ws_1", toolName: "workspace_read_file", content: "// package", isSuccess: true),
            forCallId: "call_ws_1"
        )

        let runtime = NativeAgentRuntime(inference: inference, toolExecutor: toolExecutor)
        var caughtError: (any Error)?

        do {
            let stream = runtime.run(
                history: [ChatMessage(role: .user, content: "Test whitespace canonicalization")],
                configuration: AgentRunConfiguration(maxTurns: 5)
            )
            for try await _ in stream {}
        } catch {
            caughtError = error
        }

        guard let runtimeError = caughtError as? AgentRuntimeError else {
            Issue.record("Expected AgentRuntimeError.duplicateToolCall, got: \(String(describing: caughtError))")
            return
        }

        switch runtimeError {
        case .duplicateToolCall(let toolName, _):
            #expect(toolName == "workspace_read_file")
        default:
            Issue.record("Expected .duplicateToolCall, got: \(runtimeError)")
        }

        let executedCalls = await toolExecutor.getExecutedCalls()
        #expect(executedCalls.count == 1)
        #expect(executedCalls.first?.id == "call_ws_1")
    }

    @Test("Duplicate tool call guardrail: JSON object key order variations are canonicalized as identical duplicates")
    func testDuplicateToolCallGuardrailCanonicalizesJSONObjectKeyOrder() async throws {
        let call1 = ToolCall(
            id: "call_keyorder_1",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "workspace_list_directory",
                arguments: "{\"limit\":10,\"path\":\"Sources\"}"
            )
        )
        let call2ReorderedKeys = ToolCall(
            id: "call_keyorder_2",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "workspace_list_directory",
                arguments: "{\"path\":\"Sources\",\"limit\":10}"
            )
        )

        let inference = ScriptedAgentInference(turns: [
            [.toolCall(call1), .finished],
            [.toolCall(call2ReorderedKeys), .finished]
        ])

        let toolExecutor = ScriptedAgentToolExecutor(tools: [
            AgentLoopTestHelpers.sampleWorkspaceListTool()
        ])
        await toolExecutor.registerResult(
            AgentToolResult(callId: "call_keyorder_1", toolName: "workspace_list_directory", content: "[]", isSuccess: true),
            forCallId: "call_keyorder_1"
        )

        let runtime = NativeAgentRuntime(inference: inference, toolExecutor: toolExecutor)
        var caughtError: (any Error)?

        do {
            let stream = runtime.run(
                history: [ChatMessage(role: .user, content: "Test key order canonicalization")],
                configuration: AgentRunConfiguration(maxTurns: 5)
            )
            for try await _ in stream {}
        } catch {
            caughtError = error
        }

        guard let runtimeError = caughtError as? AgentRuntimeError else {
            Issue.record("Expected AgentRuntimeError.duplicateToolCall, got: \(String(describing: caughtError))")
            return
        }

        switch runtimeError {
        case .duplicateToolCall(let toolName, _):
            #expect(toolName == "workspace_list_directory")
        default:
            Issue.record("Expected .duplicateToolCall, got: \(runtimeError)")
        }

        let executedCalls = await toolExecutor.getExecutedCalls()
        #expect(executedCalls.count == 1)
        #expect(executedCalls.first?.id == "call_keyorder_1")
    }

    @Test("Duplicate tool call guardrail: nested JSON structures differing only in formatting or key ordering are canonicalized as identical duplicates")
    func testDuplicateToolCallGuardrailCanonicalizesNestedJSONStructures() async throws {
        let call1 = ToolCall(
            id: "call_nested_1",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "workspace_read_file",
                arguments: "{\"options\":{\"encoding\":\"utf-8\",\"strict\":true},\"path\":\"data.json\"}"
            )
        )
        let call2NestedVariant = ToolCall(
            id: "call_nested_2",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "workspace_read_file",
                arguments: "{\n  \"path\": \"data.json\",\n  \"options\": {\n    \"strict\": true,\n    \"encoding\": \"utf-8\"\n  }\n}"
            )
        )

        let inference = ScriptedAgentInference(turns: [
            [.toolCall(call1), .finished],
            [.toolCall(call2NestedVariant), .finished]
        ])

        let toolExecutor = ScriptedAgentToolExecutor(tools: [
            AgentLoopTestHelpers.sampleWorkspaceReadTool()
        ])
        await toolExecutor.registerResult(
            AgentToolResult(callId: "call_nested_1", toolName: "workspace_read_file", content: "{\"data\":1}", isSuccess: true),
            forCallId: "call_nested_1"
        )

        let runtime = NativeAgentRuntime(inference: inference, toolExecutor: toolExecutor)
        var caughtError: (any Error)?

        do {
            let stream = runtime.run(
                history: [ChatMessage(role: .user, content: "Test nested JSON canonicalization")],
                configuration: AgentRunConfiguration(maxTurns: 5)
            )
            for try await _ in stream {}
        } catch {
            caughtError = error
        }

        guard let runtimeError = caughtError as? AgentRuntimeError else {
            Issue.record("Expected AgentRuntimeError.duplicateToolCall, got: \(String(describing: caughtError))")
            return
        }

        switch runtimeError {
        case .duplicateToolCall(let toolName, _):
            #expect(toolName == "workspace_read_file")
        default:
            Issue.record("Expected .duplicateToolCall, got: \(runtimeError)")
        }

        let executedCalls = await toolExecutor.getExecutedCalls()
        #expect(executedCalls.count == 1)
        #expect(executedCalls.first?.id == "call_nested_1")
    }

    @Test("Duplicate tool call guardrail: malformed non-JSON strings compare safely without crashing and detect identical malformed arguments")
    func testDuplicateToolCallGuardrailSafelyHandlesMalformedRawStrings() async throws {
        let malformedString = "{invalid json unquoted key: 123"
        let call1 = ToolCall(
            id: "call_malformed_1",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "workspace_read_file",
                arguments: malformedString
            )
        )
        let call2SameMalformed = ToolCall(
            id: "call_malformed_2",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "workspace_read_file",
                arguments: malformedString
            )
        )

        let inference = ScriptedAgentInference(turns: [
            [.toolCall(call1), .finished],
            [.toolCall(call2SameMalformed), .finished]
        ])

        let toolExecutor = ScriptedAgentToolExecutor(tools: [
            AgentLoopTestHelpers.sampleWorkspaceReadTool()
        ])
        await toolExecutor.registerResult(
            AgentToolResult(callId: "call_malformed_1", toolName: "workspace_read_file", content: "data", isSuccess: true),
            forCallId: "call_malformed_1"
        )

        let runtime = NativeAgentRuntime(inference: inference, toolExecutor: toolExecutor)
        var caughtError: (any Error)?

        do {
            let stream = runtime.run(
                history: [ChatMessage(role: .user, content: "Test malformed string comparison")],
                configuration: AgentRunConfiguration(maxTurns: 5)
            )
            for try await _ in stream {}
        } catch {
            caughtError = error
        }

        guard let runtimeError = caughtError as? AgentRuntimeError else {
            Issue.record("Expected AgentRuntimeError.duplicateToolCall, got: \(String(describing: caughtError))")
            return
        }

        switch runtimeError {
        case .duplicateToolCall(let toolName, let arguments):
            #expect(toolName == "workspace_read_file")
            #expect(arguments == malformedString)
        default:
            Issue.record("Expected .duplicateToolCall, got: \(runtimeError)")
        }

        let executedCalls = await toolExecutor.getExecutedCalls()
        #expect(executedCalls.count == 1)
        #expect(executedCalls.first?.id == "call_malformed_1")
    }


    @Test("Task cancellation propagates as CancellationError, halts further execution, and emits no finished event")
    func testTaskCancellationPropagatesAndHalts() async throws {
        let toolCall = ToolCall(
            id: "call_cancel_test",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "workspace_read_file",
                arguments: "{\"path\":\"big.txt\"}"
            )
        )

        let inference = ScriptedAgentInference(turns: [
            [
                .toolCall(toolCall),
                .finished
            ],
            [
                .contentDelta("Should never be reached"),
                .finished
            ]
        ])

        let toolExecutor = ScriptedAgentToolExecutor(tools: [
            AgentLoopTestHelpers.sampleWorkspaceReadTool()
        ])

        let gate = CancellationGate()

        // Use a deterministic gate to know when the tool execution has started, then suspend until cancelled
        await toolExecutor.setCustomHandler { call in
            await gate.signalStart()
            // Suspend until cancelled
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return AgentToolResult(callId: call.id, toolName: call.function.name, content: "done", isSuccess: true)
        }

        let runtime = NativeAgentRuntime(
            inference: inference,
            toolExecutor: toolExecutor
        )

        let task = Task {
            var events: [AgentEvent] = []
            let stream = runtime.run(
                history: [ChatMessage(role: .user, content: "Cancel me")],
                configuration: AgentRunConfiguration(maxTurns: 5)
            )
            for try await event in stream {
                events.append(event)
            }
            return events
        }

        // Wait deterministically for the tool execution to start
        await gate.waitForStart()
        task.cancel()

        var caughtCancellation = false
        var eventsResult: [AgentEvent] = []
        do {
            eventsResult = try await task.value
            Issue.record("Expected Task to throw CancellationError, but it completed")
        } catch is CancellationError {
            caughtCancellation = true
        } catch {
            Issue.record("Expected CancellationError, but caught unrelated error: \(error)")
        }

        #expect(caughtCancellation)
        #expect(!eventsResult.contains(.finished))

        // Ensure turn 2 was never executed
        let transcripts = await inference.getCapturedTranscripts()
        #expect(transcripts.count <= 1)
    }

    @Test("Thrown non-cancellation tool executor error containing absolute paths or secrets produces generic sanitized failure result without leaking error description")
    func testToolExecutorThrowingSensitiveErrorIsSanitizedWithoutLeakingDescription() async throws {
        struct SensitiveToolExecutionError: LocalizedError {
            var errorDescription: String? {
                "Failed to open /Users/adrian/secure_workspace/.env.secret: private_key=sk-live-999888777 revealed"
            }
        }

        let toolCall = ToolCall(
            id: "call_sensitive_err_1",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "workspace_read_file",
                arguments: "{\"path\":\".env.secret\"}"
            )
        )

        let inference = ScriptedAgentInference(turns: [
            // Turn 1: Model requests tool
            [
                .toolCall(toolCall),
                .finished
            ],
            // Turn 2: Model receives sanitized failure and provides recovery text
            [
                .contentDelta("I could not access the requested file due to an error."),
                .finished
            ]
        ])

        let toolExecutor = ScriptedAgentToolExecutor(tools: [
            AgentLoopTestHelpers.sampleWorkspaceReadTool()
        ])
        await toolExecutor.setCustomHandler { _ in
            throw SensitiveToolExecutionError()
        }

        let runtime = NativeAgentRuntime(
            inference: inference,
            toolExecutor: toolExecutor
        )

        var receivedEvents: [AgentEvent] = []
        let stream = runtime.run(
            history: [ChatMessage(role: .user, content: "Read secret file")],
            configuration: AgentRunConfiguration(maxTurns: 5)
        )

        for try await event in stream {
            receivedEvents.append(event)
        }

        // 1. Verify toolCompleted event carries sanitized result
        let completedEvent = receivedEvents.first { event in
            if case .toolCompleted(let result) = event {
                return result.callId == "call_sensitive_err_1"
            }
            return false
        }

        guard case .toolCompleted(let result) = completedEvent else {
            Issue.record("Expected toolCompleted event for call_sensitive_err_1")
            return
        }

        #expect(result.isSuccess == false)
        #expect(result.callId == "call_sensitive_err_1")
        #expect(result.toolName == "workspace_read_file")
        #expect(!result.content.contains("/Users/"))
        #expect(!result.content.contains("sk-live-"))
        #expect(!result.content.contains("Failed to open"))
        #expect(result.content != SensitiveToolExecutionError().localizedDescription)

        // 2. Verify Turn 2 transcript does not leak sensitive description to inference model
        let transcripts = await inference.getCapturedTranscripts()
        #expect(transcripts.count == 2)
        if transcripts.count >= 2 {
            let turn2Messages = transcripts[1]
            guard let toolMsg = turn2Messages.first(where: { $0.role == .tool && $0.toolCallId == "call_sensitive_err_1" }) else {
                Issue.record("Expected tool response message in turn 2 transcript")
                return
            }
            let toolContent = toolMsg.content ?? ""
            #expect(!toolContent.contains("/Users/"))
            #expect(!toolContent.contains("sk-live-"))
            #expect(!toolContent.contains("Failed to open"))
            #expect(toolContent != SensitiveToolExecutionError().localizedDescription)
        }
    }
}
