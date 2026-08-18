import Foundation
import QwenPrimeCommandProtocol

// MARK: - Agent Inference Streaming Protocol

/// Minimal interface for streaming chat completion turns in the agent loop.
public protocol AgentInferenceStreaming: Sendable {
    func streamChat(
        messages: [ChatCompletionMessage],
        tools: [ToolDefinition]?,
        configuration: AgentRunConfiguration
    ) async throws -> AsyncThrowingStream<StreamEvent, Error>
}

// MARK: - Agent Tool Executing Protocol

/// Minimal interface for tool execution and definition discovery.
public protocol AgentToolExecuting: Sendable {
    var tools: [ToolDefinition] { get async }
    func execute(_ call: ToolCall) async throws -> AgentToolResult
}

public protocol WorkspaceApprovalRequesting: Sendable {
    func requestApproval(
        call: ToolCall,
        payload: WorkspaceApprovalPayload
    ) async throws -> ToolApprovalDecision
}

public protocol WorkspaceCommandExecuting: Sendable {
    func prepare(
        _ proposal: WorkspaceCommandProposal
    ) async throws -> WorkspaceCommandProposal

    func execute(
        _ proposal: WorkspaceCommandProposal
    ) async throws -> CommandExecutionResponse
}

public extension WorkspaceCommandExecuting {
    func prepare(
        _ proposal: WorkspaceCommandProposal
    ) async throws -> WorkspaceCommandProposal {
        proposal
    }
}

// MARK: - ReadOnlyWorkspaceToolBroker Conformance

extension ReadOnlyWorkspaceToolBroker: AgentToolExecuting {}

// MARK: - Qwen Agent Inference Adapter

/// Thin bridge adapting QwenClient to the AgentInferenceStreaming protocol.
public struct QwenAgentInferenceAdapter: AgentInferenceStreaming {
    public let client: QwenClient

    public init(
        client: QwenClient = .shared
    ) {
        self.client = client
    }

    public func streamChat(
        messages: [ChatCompletionMessage],
        tools: [ToolDefinition]?,
        configuration: AgentRunConfiguration
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        await client.streamChat(
            messages: messages,
            tools: tools,
            baseURL: configuration.baseURL,
            model: configuration.model,
            temperature: configuration.temperature,
            systemPrompt: configuration.systemPrompt,
            isThinkingEnabled: configuration.isThinkingEnabled,
            maxCompletionTokens: configuration.maxCompletionTokens,
            maxReasoningTokens: configuration.maxReasoningTokens
        )
    }
}
