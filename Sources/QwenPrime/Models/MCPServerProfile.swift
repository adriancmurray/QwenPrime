import Foundation

public struct MCPServerProfile: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var displayName: String
    public var endpoint: String
    public var isEnabled: Bool

    public init(
        id: String,
        displayName: String,
        endpoint: String,
        isEnabled: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.endpoint = endpoint
        self.isEnabled = isEnabled
    }

    public func configuration() throws -> MCPServerConfiguration {
        try MCPServerConfiguration(
            id: id,
            displayName: displayName,
            endpoint: endpoint
        )
    }
}

public struct MCPDiscoveredTool: Identifiable, Sendable, Equatable {
    public var id: String { name }
    public let name: String
    public let description: String?

    public init(name: String, description: String?) {
        self.name = name
        self.description = description
    }
}

public enum MCPServerConnectionState: Sendable, Equatable {
    case idle
    case testing
    case connected(tools: [MCPDiscoveredTool])
    case failed(message: String)
}

public typealias MCPClientFactory = @Sendable (
    MCPServerConfiguration
) async throws -> any MCPClientServing
