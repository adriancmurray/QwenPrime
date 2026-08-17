import Testing
import Foundation
@testable import QwenPrime

@Suite("Agent Message Projection and Accumulator Contract Tests")
struct AgentMessageProjectionTests {

    // MARK: - Reasoning and Content Delta Accumulation

    @Test("Applying reasoningDelta and contentDelta accumulates text deterministically onto assistant ChatMessage")
    func testReasoningAndContentDeltaAccumulation() {
        let initialMessage = ChatMessage(
            role: .assistant,
            content: "",
            thinkingContent: "",
            isStreaming: true
        )

        var projection = AgentMessageProjection(message: initialMessage)

        projection.apply(.reasoningDelta("I will investigate the directory layout.\n"))
        projection.apply(.reasoningDelta("Next, I will inspect Sources/QwenPrime."))
        projection.apply(.contentDelta("Here is the "))
        projection.apply(.contentDelta("analysis of your project."))

        #expect(projection.message.thinkingContent == "I will investigate the directory layout.\nNext, I will inspect Sources/QwenPrime.")
        #expect(projection.message.content == "Here is the analysis of your project.")
        #expect(projection.message.isStreaming == true)
        #expect(projection.message.role == .assistant)
    }

    // MARK: - Usage Stats Recording

    @Test("Applying usage event records GenerationStats on ChatMessage")
    func testUsageStatsRecording() {
        let initialMessage = ChatMessage(
            role: .assistant,
            content: "Response",
            isStreaming: true
        )

        var projection = AgentMessageProjection(message: initialMessage)

        let stats = GenerationStats(
            promptTokens: 128,
            completionTokens: 64,
            tokensPerSecond: 38.5,
            latencySeconds: 1.66,
            timeToFirstTokenSeconds: 0.08,
            speculativeAcceptanceRate: 0.72,
            acceptedDraftTokens: 18,
            speculativeCycles: 25,
            prefillSeconds: 0.12,
            prefillTokensPerSecond: 1066.6,
            prefillTokensComputed: 128,
            prefillTokensRestored: 0,
            prefixCacheHitTokens: 0,
            reasoningTokens: 24,
            reasoningSeconds: 0.5,
            isThroughputEstimated: false
        )

        projection.apply(.usage(stats))

        #expect(projection.message.stats == stats)
        #expect(projection.message.stats?.promptTokens == 128)
        #expect(projection.message.stats?.completionTokens == 64)
        #expect(projection.message.stats?.speculativeAcceptanceRate == 0.72)
    }

    // MARK: - Tool Lifecycle: toolRequested, toolStarted, toolCompleted

    @Test("toolRequested creates running ToolExecution and toolCompleted updates it by id")
    func testToolRequestedAndCompletedLifecycle() {
        let initialMessage = ChatMessage(
            role: .assistant,
            content: "",
            isStreaming: true
        )

        var projection = AgentMessageProjection(message: initialMessage)

        let call = ToolCall(
            id: "call_read_package",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "workspace_read_file",
                arguments: "{\"path\":\"Package.swift\"}"
            )
        )

        // 1. toolRequested creates a running ToolExecution
        projection.apply(.toolRequested(call))

        #expect(projection.message.toolExecutions.count == 1)
        let runningTool = projection.message.toolExecutions[0]
        #expect(runningTool.id == "call_read_package")
        #expect(runningTool.toolName == "workspace_read_file")
        #expect(runningTool.input == "{\"path\":\"Package.swift\"}")
        #expect(runningTool.output == nil)
        #expect(runningTool.isRunning == true)
        #expect(runningTool.isSuccess == nil)

        // 2. toolStarted preserves running state
        projection.apply(.toolStarted(callId: "call_read_package", toolName: "workspace_read_file"))
        #expect(projection.message.toolExecutions[0].isRunning == true)

        // 3. toolCompleted updates execution by matching callId
        let result = AgentToolResult(
            callId: "call_read_package",
            toolName: "workspace_read_file",
            content: "// swift-tools-version: 6.0\nimport PackageDescription",
            isSuccess: true
        )
        projection.apply(.toolCompleted(result))

        #expect(projection.message.toolExecutions.count == 1)
        let completedTool = projection.message.toolExecutions[0]
        #expect(completedTool.id == "call_read_package")
        #expect(completedTool.toolName == "workspace_read_file")
        #expect(completedTool.output == "// swift-tools-version: 6.0\nimport PackageDescription")
        #expect(completedTool.isRunning == false)
        #expect(completedTool.isSuccess == true)
    }

    // MARK: - Missing toolRequested Event Normalization

    @Test("toolCompleted normalizes completion even if preceding toolRequested event was missing")
    func testToolCompletedNormalizesMissingRequestedEvent() {
        let initialMessage = ChatMessage(
            role: .assistant,
            content: "",
            isStreaming: true
        )

        var projection = AgentMessageProjection(message: initialMessage)

        // toolCompleted arrives without prior toolRequested
        let unpromptedResult = AgentToolResult(
            callId: "call_unprompted_001",
            toolName: "workspace_list_directory",
            content: "[\"Package.swift\", \"Sources\"]",
            isSuccess: true
        )
        projection.apply(.toolCompleted(unpromptedResult))

        #expect(projection.message.toolExecutions.count == 1)
        let normalizedTool = projection.message.toolExecutions[0]
        #expect(normalizedTool.id == "call_unprompted_001")
        #expect(normalizedTool.toolName == "workspace_list_directory")
        #expect(normalizedTool.output == "[\"Package.swift\", \"Sources\"]")
        #expect(normalizedTool.isRunning == false)
        #expect(normalizedTool.isSuccess == true)
    }

    // MARK: - Output Capping to 32 KiB and UTF-8 Scalar Protection

    @Test("Persisted tool output under 32 KiB cap is stored unmodified without truncation marker")
    func testToolOutputUnderCapUnmodified() {
        let initialMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        var projection = AgentMessageProjection(message: initialMessage)

        let smallContent = String(repeating: "A", count: 1024)
        let result = AgentToolResult(
            callId: "call_small",
            toolName: "workspace_read_file",
            content: smallContent,
            isSuccess: true
        )
        projection.apply(.toolCompleted(result))

        #expect(projection.message.toolExecutions.first?.output == smallContent)
    }

    @Test("Persisted tool output exceeding 32 KiB (32,768 bytes) is capped with truncation marker within limit")
    func testToolOutputExceeding32KiBCappedWithMarker() {
        let initialMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        var projection = AgentMessageProjection(message: initialMessage)

        // 64 KiB ASCII payload
        let largeContent = String(repeating: "Line of output content.\n", count: 3000)
        #expect(largeContent.utf8.count > 32 * 1024)

        let result = AgentToolResult(
            callId: "call_large_ascii",
            toolName: "workspace_read_file",
            content: largeContent,
            isSuccess: true
        )
        projection.apply(.toolCompleted(result))

        guard let output = projection.message.toolExecutions.first?.output else {
            Issue.record("Expected completed tool output")
            return
        }

        let maxBytes = 32 * 1024 // 32,768 bytes
        #expect(output.utf8.count <= maxBytes, "Persisted tool output must not exceed 32 KiB cap")
        #expect(output.contains("truncated") || output.contains("..."), "Output must contain a short truncation marker")
    }

    @Test("Truncating large tool output across multibyte UTF-8 characters preserves valid UTF-8 without splitting scalars")
    func testToolOutputTruncationPreservesValidMultibyteUTF8() {
        let initialMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        var projection = AgentMessageProjection(message: initialMessage)

        // Multibyte 4-byte emoji and 3-byte CJK repeating pattern
        let multibytePattern = "🚀 Prime 系统 ✨ " // 4-byte emoji, spaces, 3-byte Chinese characters
        let repeatCount = (35 * 1024) / multibytePattern.utf8.count
        let multibyteContent = String(repeating: multibytePattern, count: repeatCount)
        #expect(multibyteContent.utf8.count > 32 * 1024)

        let result = AgentToolResult(
            callId: "call_multibyte",
            toolName: "workspace_read_file",
            content: multibyteContent,
            isSuccess: true
        )
        projection.apply(.toolCompleted(result))

        guard let output = projection.message.toolExecutions.first?.output else {
            Issue.record("Expected completed tool output")
            return
        }

        let maxBytes = 32 * 1024
        #expect(output.utf8.count <= maxBytes)

        // Verify output data forms valid UTF-8 string without replacement characters or split codepoints
        let utf8Data = Data(output.utf8)
        let roundtripString = String(data: utf8Data, encoding: .utf8)
        #expect(roundtripString != nil, "Truncated output must remain valid UTF-8")
        #expect(!output.contains("\u{FFFD}"), "Truncation must never introduce Unicode replacement characters")
    }

    // MARK: - Stream Completion on Finished

    @Test("finished event marks isStreaming false on ChatMessage")
    func testFinishedEventSetsStreamingFalse() {
        let initialMessage = ChatMessage(
            role: .assistant,
            content: "",
            isStreaming: true
        )

        var projection = AgentMessageProjection(message: initialMessage)
        #expect(projection.message.isStreaming == true)

        projection.apply(.reasoningDelta("Thinking..."))
        projection.apply(.contentDelta("Final Answer."))
        #expect(projection.message.isStreaming == true)

        projection.apply(.finished)
        #expect(projection.message.isStreaming == false)
        #expect(projection.message.content == "Final Answer.")
        #expect(projection.message.thinkingContent == "Thinking...")
    }

    // MARK: - Identity and Timestamp Preservation

    @Test("AgentMessageProjection initialization preserves exact ChatMessage id and createdAt")
    func testInitializationPreservesMessageIdentityAndCreatedAt() {
        let customId = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F") ?? UUID()
        let customDate = Date(timeIntervalSince1970: 1_700_000_000)
        let initialMessage = ChatMessage(
            id: customId,
            role: .assistant,
            content: "Initial content",
            thinkingContent: "Initial thinking",
            isStreaming: true,
            createdAt: customDate
        )

        let projection = AgentMessageProjection(message: initialMessage)

        #expect(projection.message.id == customId)
        #expect(projection.message.createdAt == customDate)
    }

    // MARK: - Deterministic Lifecycle Ordering & Consolidated Reasoning

    @Test("Multiple tool executions maintain strict request order across interleaved events")
    func testDeterministicToolLifecycleOrdering() {
        let initialMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        var projection = AgentMessageProjection(message: initialMessage)

        let call1 = ToolCall(id: "call_1", function: .init(name: "workspace_list_directory", arguments: "{\"path\":\"Sources\"}"))
        let call2 = ToolCall(id: "call_2", function: .init(name: "workspace_read_file", arguments: "{\"path\":\"Sources/App.swift\"}"))
        let call3 = ToolCall(id: "call_3", function: .init(name: "workspace_read_file", arguments: "{\"path\":\"Package.swift\"}"))

        // Request tools 1, 2, 3 in sequence
        projection.apply(.toolRequested(call1))
        projection.apply(.toolRequested(call2))
        projection.apply(.toolRequested(call3))

        // Complete tools out of order: 2, 1, 3
        projection.apply(.toolCompleted(AgentToolResult(callId: "call_2", toolName: "workspace_read_file", content: "App.swift content", isSuccess: true)))
        projection.apply(.toolCompleted(AgentToolResult(callId: "call_1", toolName: "workspace_list_directory", content: "[\"App.swift\"]", isSuccess: true)))
        projection.apply(.toolCompleted(AgentToolResult(callId: "call_3", toolName: "workspace_read_file", content: "Package.swift content", isSuccess: true)))

        #expect(projection.message.toolExecutions.count == 3)
        // Ordering in message.toolExecutions MUST remain deterministic [call_1, call_2, call_3]
        #expect(projection.message.toolExecutions.map(\.id) == ["call_1", "call_2", "call_3"])
        #expect(projection.message.toolExecutions[0].output == "[\"App.swift\"]")
        #expect(projection.message.toolExecutions[1].output == "App.swift content")
        #expect(projection.message.toolExecutions[2].output == "Package.swift content")
    }

    @Test("Projection produces deterministic state when replayed from identical event sequences")
    func testDeterministicProjectionReplay() {
        let events: [AgentEvent] = [
            .reasoningDelta("Phase 1: list files\n"),
            .toolRequested(ToolCall(id: "call_list", function: .init(name: "workspace_list_directory", arguments: "{\"path\":\".\"}"))),
            .toolStarted(callId: "call_list", toolName: "workspace_list_directory"),
            .toolCompleted(AgentToolResult(callId: "call_list", toolName: "workspace_list_directory", content: "[\"Package.swift\"]", isSuccess: true)),
            .reasoningDelta("Phase 2: summarize\n"),
            .contentDelta("Found Package.swift."),
            .usage(GenerationStats(promptTokens: 40, completionTokens: 20, tokensPerSecond: 30.0, latencySeconds: 1.0, isThroughputEstimated: false)),
            .finished
        ]

        let initialMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        var proj1 = AgentMessageProjection(message: initialMessage)
        for event in events { proj1.apply(event) }

        var proj2 = AgentMessageProjection(message: initialMessage)
        for event in events { proj2.apply(event) }

        #expect(proj1.message == proj2.message)
        #expect(proj1.message.isStreaming == false)
        #expect(proj1.message.content == "Found Package.swift.")
        #expect(proj1.message.toolExecutions.count == 1)
        #expect(proj1.message.toolExecutions[0].isSuccess == true)

        // Consolidated reasoning compatibility
        let resolved = ReasoningPresentation.resolve(
            hiddenThinking: proj1.message.thinkingContent,
            content: proj1.message.content
        )
        #expect(resolved.thinking == "Phase 1: list files\nPhase 2: summarize")
        #expect(resolved.answer == "Found Package.swift.")
    }
}
