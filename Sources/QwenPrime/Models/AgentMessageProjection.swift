import Foundation

/// Pure projection accumulator applying `AgentEvent` streams deterministically onto an assistant `ChatMessage`.
public struct AgentMessageProjection: Sendable, Equatable {
    public var message: ChatMessage

    public static let maxToolOutputBytes: Int = 32 * 1024
    public static let truncationMarker: String = "\n\n... [output truncated]"

    public init(message: ChatMessage) {
        self.message = message
    }

    /// Caps persisted tool output to exactly 32 KiB including a short marker while preserving valid UTF-8 character boundaries.
    public static func capToolOutput(_ content: String, maxBytes: Int = maxToolOutputBytes) -> String {
        guard content.utf8.count > maxBytes else {
            return content
        }

        let markerBytes = truncationMarker.utf8.count
        let targetBytes = max(0, maxBytes - markerBytes)

        var currentBytes = 0
        var lastValidIndex = content.startIndex

        for index in content.indices {
            let char = content[index]
            let charBytes = char.utf8.count
            if currentBytes + charBytes > targetBytes {
                break
            }
            currentBytes += charBytes
            lastValidIndex = content.index(after: index)
        }

        let prefix = String(content[..<lastValidIndex])
        return prefix + truncationMarker
    }

    /// Deterministically applies an `AgentEvent` to the projected assistant `ChatMessage`.
    public mutating func apply(_ event: AgentEvent) {
        switch event {
        case .reasoningDelta(let delta):
            if let existing = message.thinkingContent {
                message.thinkingContent = existing + delta
            } else {
                message.thinkingContent = delta
            }

        case .contentDelta(let delta):
            message.content += delta

        case .contentReset(let content):
            message.content = content

        case .toolRequested(let call):
            if let index = message.toolExecutions.firstIndex(where: { $0.id == call.id }) {
                message.toolExecutions[index].toolName = call.function.name
                message.toolExecutions[index].input = call.function.arguments
                message.toolExecutions[index].isRunning = true
            } else {
                let execution = ToolExecution(
                    id: call.id,
                    toolName: call.function.name,
                    input: call.function.arguments,
                    output: nil,
                    isRunning: true,
                    isSuccess: nil
                )
                message.toolExecutions.append(execution)
            }

        case .toolStarted(let callId, let toolName):
            if let index = message.toolExecutions.firstIndex(where: { $0.id == callId }) {
                message.toolExecutions[index].toolName = toolName
                message.toolExecutions[index].isRunning = true
            } else {
                let execution = ToolExecution(
                    id: callId,
                    toolName: toolName,
                    input: "",
                    output: nil,
                    isRunning: true,
                    isSuccess: nil
                )
                message.toolExecutions.append(execution)
            }

        case .toolCompleted(let result):
            let cappedOutput = Self.capToolOutput(result.content)
            if let index = message.toolExecutions.firstIndex(where: { $0.id == result.callId }) {
                message.toolExecutions[index].toolName = result.toolName
                message.toolExecutions[index].output = cappedOutput
                message.toolExecutions[index].isRunning = false
                message.toolExecutions[index].isSuccess = result.isSuccess
                message.toolExecutions[index].mutationProposal = result.mutationProposal
                message.toolExecutions[index].approvalState = result.approvalState
                message.toolExecutions[index].commandProposal = result.commandProposal
            } else {
                let execution = ToolExecution(
                    id: result.callId,
                    toolName: result.toolName,
                    input: "",
                    output: cappedOutput,
                    isRunning: false,
                    isSuccess: result.isSuccess,
                    mutationProposal: result.mutationProposal,
                    approvalState: result.approvalState,
                    commandProposal: result.commandProposal
                )
                message.toolExecutions.append(execution)
            }

        case .usage(let stats):
            message.stats = stats

        case .finished:
            message.isStreaming = false
        }
    }
}
