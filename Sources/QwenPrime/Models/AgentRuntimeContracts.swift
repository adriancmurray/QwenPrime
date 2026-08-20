import Foundation

// MARK: - Agent Run Configuration

/// Runtime execution configuration for the native agent loop.
public struct AgentRunConfiguration: Sendable, Equatable {
    public static let defaultMaxTurns = 12

    public var systemPrompt: String?
    public var maxTurns: Int
    public var baseURL: String
    public var temperature: Double
    public var model: String
    public var isThinkingEnabled: Bool
    public var maxCompletionTokens: Int
    public var maxReasoningTokens: Int

    public init(
        systemPrompt: String? = nil,
        maxTurns: Int = Self.defaultMaxTurns,
        baseURL: String = AppPreferences.defaultBaseURL,
        temperature: Double = 0.1,
        model: String = AppPreferences.defaultModel,
        isThinkingEnabled: Bool = true,
        maxCompletionTokens: Int = 1024,
        maxReasoningTokens: Int = 96
    ) {
        self.systemPrompt = systemPrompt
        self.maxTurns = maxTurns
        self.baseURL = baseURL
        self.temperature = temperature
        self.model = model
        self.isThinkingEnabled = isThinkingEnabled
        self.maxCompletionTokens = maxCompletionTokens
        self.maxReasoningTokens = maxReasoningTokens
    }
}

// MARK: - Agent Runtime Events

/// Lifecycle and stream events emitted by the native agent runtime during execution.
public enum AgentEvent: Sendable, Equatable {
    case reasoningDelta(String)
    case contentDelta(String)
    case contentReset(String)
    case toolRequested(ToolCall)
    case toolStarted(callId: String, toolName: String)
    case toolCompleted(AgentToolResult)
    case usage(GenerationStats)
    case finished
}

// MARK: - Agent Runtime Errors

/// Strongly typed runtime errors for guardrail violations during agent execution.
public enum AgentRuntimeError: Error, Sendable, Equatable, LocalizedError {
    case maxTurnsExceeded(limit: Int)
    case duplicateToolCall(toolName: String, arguments: String)

    public var errorDescription: String? {
        switch self {
        case .maxTurnsExceeded(let limit):
            return "Agent reached the maximum turn limit of \(limit)."
        case .duplicateToolCall(let toolName, let arguments):
            return "Duplicate tool call detected for '\(toolName)' with arguments: \(arguments)"
        }
    }
}
