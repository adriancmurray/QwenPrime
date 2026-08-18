import Foundation

public enum AgentSkillSource: String, Codable, Sendable, Equatable {
    case workspace
    case user
}

public struct AgentSkill: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let instructions: String
    public let source: AgentSkillSource
    public let fileURL: URL

    public init(
        name: String,
        description: String,
        instructions: String,
        source: AgentSkillSource,
        fileURL: URL
    ) {
        self.name = name
        self.description = description
        self.instructions = instructions
        self.source = source
        self.fileURL = fileURL.standardizedFileURL
        self.id = "\(source.rawValue):\(self.fileURL.path)"
    }
}
