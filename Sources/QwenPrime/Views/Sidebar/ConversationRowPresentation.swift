import Foundation

public struct ConversationRowPresentation: Sendable, Equatable {
    public let preview: String
    public let timestamp: String

    public init(conversation: Conversation) {
        self.preview = Self.preview(for: conversation)
        if Calendar.current.isDateInToday(conversation.updatedAt) {
            self.timestamp = conversation.updatedAt.formatted(
                .dateTime.hour().minute()
            )
        } else {
            self.timestamp = conversation.updatedAt.formatted(
                .dateTime.month(.abbreviated).day()
            )
        }
    }

    private static func preview(for conversation: Conversation) -> String {
        guard let message = conversation.messages.last else {
            return "No messages"
        }
        let source: String
        if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            source = message.content
        } else if !(message.thinkingContent ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Reasoning…"
        } else {
            return message.isStreaming ? "Starting…" : "No response"
        }

        let patterns = [
            #"```[A-Za-z0-9_+.-]*"#,
            #"(?m)^#{1,6}\s*"#,
            #"[*_>`~]"#,
        ]
        let plain = patterns.reduce(source) { value, pattern in
            value.replacingOccurrences(
                of: pattern,
                with: " ",
                options: .regularExpression
            )
        }
        return plain
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
