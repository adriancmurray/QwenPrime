import Foundation

public struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var role: MessageRole
    public var content: String
    public var thinkingContent: String?
    public var isThinkingExpanded: Bool
    public var stats: GenerationStats?
    public var isStreaming: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        thinkingContent: String? = nil,
        isThinkingExpanded: Bool = false,
        stats: GenerationStats? = nil,
        isStreaming: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.isThinkingExpanded = isThinkingExpanded
        self.stats = stats
        self.isStreaming = isStreaming
        self.createdAt = createdAt
    }
}
