import Foundation
import SwiftMCPStore

public enum AgentToolRoutingMode: String, Sendable, Equatable {
    case ranked
    case fullCatalog = "full"

    public init(environmentValue: String?) {
        self = environmentValue?.lowercased() == Self.ranked.rawValue ? .ranked : .fullCatalog
    }
}

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

    public var estimatedSchemaTokens: Int {
        tools.reduce(into: 0) { total, definition in
            total += TokenEstimation.utf8BudgetCount(
                for: Self.schemaJSON(for: definition)
            )
        }
    }

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

    /// Selects a stable, bounded tool catalog using Engur's dependency-free Swift ranker.
    /// Explicit tool names always win; low-confidence requests retain the complete catalog.
    public func selectingRelevantTools(
        for text: String,
        maximumCount: Int = 5,
        mode: AgentToolRoutingMode = .ranked
    ) -> AgentToolRegistry {
        let explicitlyMentioned = advertisingExplicitToolMentions(in: text)
        guard explicitlyMentioned.tools.count == tools.count else {
            return explicitlyMentioned
        }
        guard mode == .ranked else { return self }
        guard maximumCount > 0, tools.count > maximumCount else { return self }

        let index = SemanticIndexSimulator()
        index.loadTools(
            catalog.map { entry in
                let schemaJSON = Self.schemaJSON(for: entry.definition)
                return IndexableTool(
                    name: entry.definition.function.name,
                    description: entry.definition.function.description ?? "",
                    serverName: entry.providerDisplayName,
                    schemaJSON: schemaJSON,
                    estimatedTokens: TokenEstimation.utf8BasedCount(
                        for: schemaJSON
                    )
                )
            }
        )

        let ranked = index.search(query: text, topK: maximumCount)
        guard let bestMatch = ranked.first, bestMatch.confidence >= 0.2 else { return self }

        let entriesByName = Dictionary(
            uniqueKeysWithValues: catalog.map { ($0.definition.function.name, $0) }
        )
        var selectedNamesInOrder: [String] = []
        let clauseText = text.replacingOccurrences(
            of: " and ",
            with: "\n",
            options: [.caseInsensitive]
        )
        let clauses = clauseText.components(
            separatedBy: CharacterSet(charactersIn: ",.;\n")
        )
        for clause in clauses where selectedNamesInOrder.count < maximumCount {
            guard !clause.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            for result in index.search(query: clause, topK: 2)
            where selectedNamesInOrder.count < maximumCount && result.confidence >= 0.2 {
                if !selectedNamesInOrder.contains(result.tool.name) {
                    selectedNamesInOrder.append(result.tool.name)
                }
            }
        }
        for result in ranked where selectedNamesInOrder.count < maximumCount {
            if !selectedNamesInOrder.contains(result.tool.name) {
                selectedNamesInOrder.append(result.tool.name)
            }
        }
        if maximumCount >= 3 {
            for baselineName in [
                ToolName.workspaceListDirectory,
                ToolName.workspaceReadFile,
            ]
            where selectedNamesInOrder.count < maximumCount {
                if entriesByName[baselineName] != nil,
                   !selectedNamesInOrder.contains(baselineName) {
                    selectedNamesInOrder.append(baselineName)
                }
            }
        }
        let selectedCatalog = selectedNamesInOrder.compactMap { entriesByName[$0] }
        let selectedNames = Set(selectedCatalog.map { $0.definition.function.name })

        return AgentToolRegistry(
            catalog: selectedCatalog,
            executorsByToolName: executorsByToolName.filter { selectedNames.contains($0.key) }
        )
    }

    private static func schemaJSON(for definition: ToolDefinition) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(definition),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
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
