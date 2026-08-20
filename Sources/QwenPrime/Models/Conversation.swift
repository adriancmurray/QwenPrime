import Foundation

public struct Conversation: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var messages: [ChatMessage]
    public let createdAt: Date
    public var updatedAt: Date
    public var modelId: String
    public var temperature: Double
    public var systemPrompt: String?
    public var isThinkingEnabled: Bool = true
    public var projectPath: String?

    public init(
        id: UUID = UUID(),
        title: String = "New Chat",
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        modelId: String = AppPreferences.defaultModel,
        temperature: Double = 0.1,
        systemPrompt: String? = nil,
        isThinkingEnabled: Bool = true,
        projectPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.modelId = modelId
        self.temperature = temperature
        self.systemPrompt = systemPrompt
        self.isThinkingEnabled = isThinkingEnabled
        self.projectPath = projectPath
    }

    public mutating func touch() {
        self.updatedAt = Date()
    }
}
