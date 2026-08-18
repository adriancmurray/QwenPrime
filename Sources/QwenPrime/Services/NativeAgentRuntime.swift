import Foundation

/// Stateless production runtime orchestrating the agent inference and tool execution loop.
public struct NativeAgentRuntime: Sendable {
    public let inference: any AgentInferenceStreaming
    public let toolExecutor: (any AgentToolExecuting)?

    public init(
        inference: any AgentInferenceStreaming,
        toolExecutor: (any AgentToolExecuting)? = nil
    ) {
        self.inference = inference
        self.toolExecutor = toolExecutor
    }

    /// Converts persisted ChatMessage history into transient ChatCompletionMessage transport values.
    public static func buildInitialTranscript(from history: [ChatMessage]) -> [ChatCompletionMessage] {
        var transcript: [ChatCompletionMessage] = []

        for message in history {
            switch message.role {
            case .user:
                transcript.append(
                    ChatCompletionMessage(
                        role: .user,
                        content: message.content
                    )
                )
            case .assistant:
                let completedToolExecutions = message.toolExecutions.filter { !$0.isRunning && $0.isSuccess != nil }
                if !completedToolExecutions.isEmpty {
                    let toolCalls = completedToolExecutions.map { execution in
                        ToolCall(
                            id: execution.id,
                            type: "function",
                            function: ToolCall.FunctionCall(
                                name: execution.toolName,
                                arguments: execution.input
                            )
                        )
                    }
                    transcript.append(
                        ChatCompletionMessage(
                            role: .assistant,
                            content: message.content.isEmpty ? nil : message.content,
                            toolCalls: toolCalls,
                            reasoningContent: (message.thinkingContent?.isEmpty == false) ? message.thinkingContent : nil
                        )
                    )
                    for execution in completedToolExecutions {
                        transcript.append(
                            ChatCompletionMessage(
                                role: .tool,
                                content: execution.output ?? "",
                                toolCallId: execution.id
                            )
                        )
                    }
                } else {
                    transcript.append(
                        ChatCompletionMessage(
                            role: .assistant,
                            content: message.content,
                            reasoningContent: (message.thinkingContent?.isEmpty == false) ? message.thinkingContent : nil
                        )
                    )
                }
            case .system:
                transcript.append(
                    ChatCompletionMessage(
                        role: .system,
                        content: message.content
                    )
                )
            case .tool:
                // Persisted role=.tool messages cannot carry a matching tool_call_id and are omitted.
                break
            }
        }

        return transcript
    }

    /// Runs the agent loop, returning an asynchronous stream of agent events.
    public func run(
        history: [ChatMessage],
        configuration: AgentRunConfiguration = AgentRunConfiguration()
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.executeLoop(
                        history: history,
                        configuration: configuration,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable termination in
                task.cancel()
                if case .cancelled = termination {
                    continuation.finish(throwing: CancellationError())
                }
            }
        }
    }

    private struct ToolSignature: Hashable {
        let name: String
        let arguments: String
    }

    /// Canonicalizes tool call arguments for deterministic duplicate comparison.
    /// Valid JSON arguments are recursively canonicalized with sorted keys and compact formatting.
    /// Malformed non-JSON strings fall back to trimmed raw text.
    public static func canonicalizeArguments(_ rawArguments: String) -> String {
        let trimmed = rawArguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return trimmed
        }
        if JSONSerialization.isValidJSONObject(jsonObject) {
            if let canonicalData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys]),
               let canonicalString = String(data: canonicalData, encoding: .utf8) {
                return canonicalString
            }
        } else {
            if let canonicalData = try? JSONSerialization.data(withJSONObject: [jsonObject], options: [.sortedKeys]),
               let canonicalString = String(data: canonicalData, encoding: .utf8) {
                if canonicalString.hasPrefix("[") && canonicalString.hasSuffix("]") {
                    return String(canonicalString.dropFirst().dropLast())
                }
            }
        }
        return trimmed
    }

    private func executeLoop(
        history: [ChatMessage],
        configuration: AgentRunConfiguration,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws {
        var transcript = Self.buildInitialTranscript(from: history)
        let availableTools = await toolExecutor?.tools
        var executedToolSignatures = Set<ToolSignature>()
        var currentTurn = 0
        var emittedContent = ""

        while true {
            try Task.checkCancellation()

            if currentTurn >= configuration.maxTurns {
                throw AgentRuntimeError.maxTurnsExceeded(limit: configuration.maxTurns)
            }
            currentTurn += 1

            let stream = try await inference.streamChat(
                messages: transcript,
                tools: availableTools,
                configuration: configuration
            )

            var turnReasoning = ""
            var turnContent = ""
            let contentCheckpoint = emittedContent
            var turnToolCalls: [ToolCall] = []

            for try await event in stream {
                try Task.checkCancellation()

                switch event {
                case .reasoningDelta(let text):
                    turnReasoning += text
                    continuation.yield(.reasoningDelta(text))
                case .contentDelta(let text):
                    turnContent += text
                    emittedContent += text
                    continuation.yield(.contentDelta(text))
                case .toolCall(let toolCall):
                    turnToolCalls.append(toolCall)
                case .usage(let stats):
                    continuation.yield(.usage(stats))
                case .finished:
                    // Consume inner StreamEvent.finished as turn boundary
                    break
                }
            }

            try Task.checkCancellation()

            if turnToolCalls.isEmpty {
                continuation.yield(.finished)
                return
            }

            if emittedContent != contentCheckpoint {
                emittedContent = contentCheckpoint
                continuation.yield(.contentReset(contentCheckpoint))
            }

            // Append assistant message with tool calls to transcript
            let assistantMessage = ChatCompletionMessage(
                role: .assistant,
                content: turnContent.isEmpty ? nil : turnContent,
                toolCalls: turnToolCalls,
                reasoningContent: turnReasoning.isEmpty ? nil : turnReasoning
            )
            transcript.append(assistantMessage)

            // Execute each requested tool sequentially in stable index order
            for call in turnToolCalls {
                try Task.checkCancellation()

                continuation.yield(.toolRequested(call))

                let canonicalArguments = Self.canonicalizeArguments(call.function.arguments)
                let signature = ToolSignature(name: call.function.name, arguments: canonicalArguments)
                if executedToolSignatures.contains(signature) {
                    throw AgentRuntimeError.duplicateToolCall(
                        toolName: call.function.name,
                        arguments: call.function.arguments
                    )
                }
                executedToolSignatures.insert(signature)

                continuation.yield(.toolStarted(callId: call.id, toolName: call.function.name))

                let rawResult: AgentToolResult
                if let executor = toolExecutor {
                    do {
                        rawResult = try await executor.execute(call)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        rawResult = AgentToolResult(
                            callId: call.id,
                            toolName: call.function.name,
                            content: "Tool execution failed",
                            isSuccess: false
                        )
                    }
                } else {
                    rawResult = AgentToolResult(
                        callId: call.id,
                        toolName: call.function.name,
                        content: "No tool executor configured",
                        isSuccess: false
                    )
                }

                let result = AgentToolResult(
                    callId: call.id,
                    toolName: call.function.name,
                    content: rawResult.content,
                    isSuccess: rawResult.isSuccess,
                    mutationProposal: rawResult.mutationProposal,
                    approvalState: rawResult.approvalState,
                    commandProposal: rawResult.commandProposal
                )

                try Task.checkCancellation()

                continuation.yield(.toolCompleted(result))

                transcript.append(
                    ChatCompletionMessage(
                        role: .tool,
                        content: result.content,
                        toolCallId: result.callId
                    )
                )

                if result.isSuccess,
                   result.approvalState == .approved,
                   result.mutationProposal != nil {
                    executedToolSignatures.removeAll(keepingCapacity: true)
                }
            }
        }
    }
}
