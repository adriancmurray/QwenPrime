import Foundation

public enum AgentToolAuthorization: String, Sendable, Codable, Equatable {
    case readOnly
    case userApproval
}

public struct AgentToolRegistration: Sendable, Equatable {
    public let definition: ToolDefinition
    public let authorization: AgentToolAuthorization

    public init(
        definition: ToolDefinition,
        authorization: AgentToolAuthorization
    ) {
        self.definition = definition
        self.authorization = authorization
    }
}

public struct AgentToolProviderRegistration: Sendable {
    public let id: String
    public let displayName: String
    public let tools: [AgentToolRegistration]
    public let executor: any AgentToolExecuting

    public init(
        id: String,
        displayName: String,
        tools: [AgentToolRegistration],
        executor: any AgentToolExecuting
    ) {
        self.id = id
        self.displayName = displayName
        self.tools = tools
        self.executor = executor
    }
}

public struct AgentToolCatalogEntry: Sendable, Equatable {
    public let providerID: String
    public let providerDisplayName: String
    public let definition: ToolDefinition
    public let authorization: AgentToolAuthorization

    public init(
        providerID: String,
        providerDisplayName: String,
        definition: ToolDefinition,
        authorization: AgentToolAuthorization
    ) {
        self.providerID = providerID
        self.providerDisplayName = providerDisplayName
        self.definition = definition
        self.authorization = authorization
    }
}

public enum AgentToolRegistryError: Error, Sendable, Equatable, LocalizedError {
    case duplicateToolName(String)

    public var errorDescription: String? {
        switch self {
        case .duplicateToolName(let name):
            return "Duplicate tool name: \(name)"
        }
    }
}

/// Immutable routing table for native and external agent tool providers.
public struct AgentToolRegistry: AgentToolExecuting {
    public let catalog: [AgentToolCatalogEntry]
    public let tools: [ToolDefinition]
    private let executorsByToolName: [String: any AgentToolExecuting]

    public init(providers: [AgentToolProviderRegistration]) throws {
        var catalog: [AgentToolCatalogEntry] = []
        var executorsByToolName: [String: any AgentToolExecuting] = [:]

        for provider in providers {
            for tool in provider.tools {
                let name = tool.definition.function.name
                guard executorsByToolName[name] == nil else {
                    throw AgentToolRegistryError.duplicateToolName(name)
                }
                executorsByToolName[name] = provider.executor
                catalog.append(
                    AgentToolCatalogEntry(
                        providerID: provider.id,
                        providerDisplayName: provider.displayName,
                        definition: tool.definition,
                        authorization: tool.authorization
                    )
                )
            }
        }

        self.catalog = catalog
        self.tools = catalog.map(\.definition)
        self.executorsByToolName = executorsByToolName
    }

    private init(
        catalog: [AgentToolCatalogEntry],
        executorsByToolName: [String: any AgentToolExecuting]
    ) {
        self.catalog = catalog
        self.tools = catalog.map(\.definition)
        self.executorsByToolName = executorsByToolName
    }

    /// When the user names one or more registered tools, advertise only those tools to inference.
    /// Natural-language requests that do not name a tool retain the complete catalog.
    public func advertisingExplicitToolMentions(in text: String) -> AgentToolRegistry {
        let mentionedNames = Set(
            tools
                .map(\.function.name)
                .filter { text.range(of: $0, options: [.caseInsensitive]) != nil }
        )
        guard !mentionedNames.isEmpty else { return self }

        return AgentToolRegistry(
            catalog: catalog.filter {
                mentionedNames.contains($0.definition.function.name)
            },
            executorsByToolName: executorsByToolName.filter {
                mentionedNames.contains($0.key)
            }
        )
    }

    public func execute(_ call: ToolCall) async throws -> AgentToolResult {
        guard let executor = executorsByToolName[call.function.name] else {
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Unknown tool: \(call.function.name)",
                isSuccess: false
            )
        }
        return try await executor.execute(call)
    }
}
