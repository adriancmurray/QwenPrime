import Foundation
import Testing
@testable import QwenPrime

/// Thread-safe scripted inference test double for testing the agent loop.
actor ScriptedAgentInference: AgentInferenceStreaming {
    private var queuedTurns: [[StreamEvent]] = []
    private var customHandler: (@Sendable ([ChatCompletionMessage], [ToolDefinition]?, AgentRunConfiguration) async throws -> [StreamEvent])?
    private var capturedTranscripts: [[ChatCompletionMessage]] = []
    private var capturedTools: [[ToolDefinition]?] = []
    private var capturedConfigurations: [AgentRunConfiguration] = []

    init(turns: [[StreamEvent]] = []) {
        self.queuedTurns = turns
    }

    init(handler: @escaping @Sendable ([ChatCompletionMessage], [ToolDefinition]?, AgentRunConfiguration) async throws -> [StreamEvent]) {
        self.customHandler = handler
    }

    func enqueueTurn(_ events: [StreamEvent]) {
        queuedTurns.append(events)
    }

    func setCustomHandler(_ handler: @escaping @Sendable ([ChatCompletionMessage], [ToolDefinition]?, AgentRunConfiguration) async throws -> [StreamEvent]) {
        self.customHandler = handler
    }

    func getCapturedTranscripts() -> [[ChatCompletionMessage]] {
        capturedTranscripts
    }

    func getCapturedTools() -> [[ToolDefinition]?] {
        capturedTools
    }

    func getCapturedConfigurations() -> [AgentRunConfiguration] {
        capturedConfigurations
    }

    func streamChat(
        messages: [ChatCompletionMessage],
        tools: [ToolDefinition]?,
        configuration: AgentRunConfiguration
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        capturedTranscripts.append(messages)
        capturedTools.append(tools)
        capturedConfigurations.append(configuration)

        if let handler = customHandler {
            let events = try await handler(messages, tools, configuration)
            return AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }

        guard !queuedTurns.isEmpty else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NSError(
                    domain: "ScriptedAgentInference",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No more scripted turns available"]
                ))
            }
        }

        let events = queuedTurns.removeFirst()
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

/// Thread-safe gate for deterministic synchronization in concurrency tests.
actor CancellationGate {
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func waitForStart() async {
        if hasStarted { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func signalStart() {
        hasStarted = true
        startedContinuation?.resume()
        startedContinuation = nil
    }
}

/// Thread-safe scripted tool executor test double.
actor ScriptedAgentToolExecutor: AgentToolExecuting {
    var tools: [ToolDefinition]
    private var resultsByToolName: [String: AgentToolResult] = [:]
    private var resultsByCallId: [String: AgentToolResult] = [:]
    private var customHandler: (@Sendable (ToolCall) async throws -> AgentToolResult)?
    private var executedCalls: [ToolCall] = []

    init(tools: [ToolDefinition] = []) {
        self.tools = tools
    }

    func registerResult(_ result: AgentToolResult, forToolName name: String) {
        resultsByToolName[name] = result
    }

    func registerResult(_ result: AgentToolResult, forCallId callId: String) {
        resultsByCallId[callId] = result
    }

    func setCustomHandler(_ handler: @escaping @Sendable (ToolCall) async throws -> AgentToolResult) {
        self.customHandler = handler
    }

    func getExecutedCalls() -> [ToolCall] {
        executedCalls
    }

    func execute(_ call: ToolCall) async throws -> AgentToolResult {
        try Task.checkCancellation()
        executedCalls.append(call)

        if let handler = customHandler {
            return try await handler(call)
        }

        if let result = resultsByCallId[call.id] {
            return result
        }

        if let result = resultsByToolName[call.function.name] {
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: result.content,
                isSuccess: result.isSuccess
            )
        }

        return AgentToolResult(
            callId: call.id,
            toolName: call.function.name,
            content: "Unknown tool: \(call.function.name)",
            isSuccess: false
        )
    }
}

enum AgentLoopTestHelpers {
    static func sampleStats() -> GenerationStats {
        GenerationStats(
            promptTokens: 25,
            completionTokens: 50,
            tokensPerSecond: 28.5,
            latencySeconds: 1.75,
            timeToFirstTokenSeconds: 0.12,
            isThroughputEstimated: false
        )
    }

    static func sampleWorkspaceListTool() -> ToolDefinition {
        ToolDefinition(
            type: "function",
            function: ToolDefinition.FunctionDefinition(
                name: "workspace_list_directory",
                description: "List directory entries",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object(["type": .string("string")])
                    ])
                ])
            )
        )
    }

    static func sampleWorkspaceReadTool() -> ToolDefinition {
        ToolDefinition(
            type: "function",
            function: ToolDefinition.FunctionDefinition(
                name: "workspace_read_file",
                description: "Read file text",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("path")])
                ])
            )
        )
    }
}
