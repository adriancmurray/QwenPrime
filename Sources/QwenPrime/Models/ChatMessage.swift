import Foundation

public struct ToolExecution: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var toolName: String
    public var input: String
    public var output: String?
    public var isRunning: Bool
    public var isSuccess: Bool?
    public var mutationProposal: WorkspaceMutationProposal?
    public var approvalState: ToolApprovalState?

    public init(
        id: String = UUID().uuidString,
        toolName: String = "ipython",
        input: String,
        output: String? = nil,
        isRunning: Bool = false,
        isSuccess: Bool? = nil,
        mutationProposal: WorkspaceMutationProposal? = nil,
        approvalState: ToolApprovalState? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.input = input
        self.output = output
        self.isRunning = isRunning
        self.isSuccess = isSuccess
        self.mutationProposal = mutationProposal
        self.approvalState = approvalState
    }
}

public struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var role: MessageRole
    public var content: String
    public var thinkingContent: String?
    public var isThinkingExpanded: Bool
    public var toolExecutions: [ToolExecution]
    public var stats: GenerationStats?
    public var isStreaming: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        thinkingContent: String? = nil,
        isThinkingExpanded: Bool = false,
        toolExecutions: [ToolExecution] = [],
        stats: GenerationStats? = nil,
        isStreaming: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.isThinkingExpanded = isThinkingExpanded
        self.toolExecutions = toolExecutions
        self.stats = stats
        self.isStreaming = isStreaming
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, role, content, thinkingContent, isThinkingExpanded, toolExecutions, stats, isStreaming, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.role = try container.decode(MessageRole.self, forKey: .role)
        self.content = try container.decode(String.self, forKey: .content)
        self.thinkingContent = try container.decodeIfPresent(String.self, forKey: .thinkingContent)
        self.isThinkingExpanded = try container.decodeIfPresent(Bool.self, forKey: .isThinkingExpanded) ?? false
        self.toolExecutions = try container.decodeIfPresent([ToolExecution].self, forKey: .toolExecutions) ?? []
        self.stats = try container.decodeIfPresent(GenerationStats.self, forKey: .stats)
        self.isStreaming = try container.decodeIfPresent(Bool.self, forKey: .isStreaming) ?? false
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}
