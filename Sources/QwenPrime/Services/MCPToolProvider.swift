import Foundation

public struct MCPServerConfiguration: Sendable, Equatable, Codable {
    public let id: String
    public let displayName: String
    public let endpoint: URL

    public init(id: String, displayName: String, endpoint: String) throws {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty, !trimmedName.isEmpty else {
            throw MCPServerConfigurationError.missingIdentity
        }
        guard let url = URL(string: endpoint),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.user == nil,
              url.password == nil else {
            throw MCPServerConfigurationError.invalidEndpoint
        }
        let host = url.host?.lowercased()
        guard host == "localhost" || host == "127.0.0.1" || host == "::1" else {
            throw MCPServerConfigurationError.nonLoopbackEndpoint
        }
        self.id = trimmedID
        self.displayName = trimmedName
        self.endpoint = url
    }
}

public enum MCPServerConfigurationError: Error, Sendable, Equatable, LocalizedError {
    case missingIdentity
    case invalidEndpoint
    case nonLoopbackEndpoint

    public var errorDescription: String? {
        switch self {
        case .missingIdentity:
            return "The MCP server needs a name and identifier."
        case .invalidEndpoint:
            return "Enter a valid MCP Streamable HTTP endpoint without embedded credentials."
        case .nonLoopbackEndpoint:
            return "This preview accepts only localhost MCP endpoints."
        }
    }
}

public struct MCPRemoteTool: Sendable, Equatable {
    public let name: String
    public let description: String?
    public let inputSchema: JSONValue

    public init(name: String, description: String?, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct MCPRemoteToolResult: Sendable, Equatable {
    public let content: String
    public let isError: Bool

    public init(content: String, isError: Bool) {
        self.content = content
        self.isError = isError
    }
}

public protocol MCPClientServing: Sendable {
    func listTools() async throws -> [MCPRemoteTool]
    func callTool(
        name: String,
        arguments: [String: JSONValue]
    ) async throws -> MCPRemoteToolResult
    func close() async
}

public extension MCPClientServing {
    func close() async {}
}

public enum MCPToolProviderError: Error, Sendable, Equatable, LocalizedError {
    case duplicateToolName(String)
    case invalidArguments

    public var errorDescription: String? {
        switch self {
        case .duplicateToolName(let name):
            return "MCP tools become ambiguous after namespacing: \(name)"
        case .invalidArguments:
            return "MCP tool arguments must be a JSON object."
        }
    }
}

public enum MCPToolProvider {
    public static func connect(
        configuration: MCPServerConfiguration,
        client: any MCPClientServing,
        approvalRequester: (any WorkspaceApprovalRequesting)?
    ) async throws -> AgentToolProviderRegistration {
        let remoteTools = try await client.listTools()
        let providerSlug = slug(configuration.id)
        var registrations: [AgentToolRegistration] = []
        var remoteNamesByExposedName: [String: String] = [:]

        for remoteTool in remoteTools {
            let exposedName = "mcp__\(providerSlug)__\(slug(remoteTool.name))"
            guard remoteNamesByExposedName[exposedName] == nil else {
                throw MCPToolProviderError.duplicateToolName(exposedName)
            }
            remoteNamesByExposedName[exposedName] = remoteTool.name
            registrations.append(
                AgentToolRegistration(
                    definition: ToolDefinition(
                        function: .init(
                            name: exposedName,
                            description: remoteTool.description,
                            parameters: remoteTool.inputSchema
                        )
                    ),
                    authorization: .userApproval
                )
            )
        }

        let executor = MCPToolExecutor(
            providerDisplayName: configuration.displayName,
            remoteNamesByExposedName: remoteNamesByExposedName,
            client: client,
            approvalRequester: approvalRequester
        )
        return AgentToolProviderRegistration(
            id: "mcp.\(providerSlug)",
            displayName: configuration.displayName,
            tools: registrations,
            executor: executor
        )
    }

    private static func slug(_ raw: String) -> String {
        let scalars = raw.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "_"
        }
        let result = String(scalars)
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
        return result.isEmpty ? "tool" : result
    }
}

private actor MCPToolExecutor: AgentToolExecuting {
    let providerDisplayName: String
    let remoteNamesByExposedName: [String: String]
    let client: any MCPClientServing
    let approvalRequester: (any WorkspaceApprovalRequesting)?

    nonisolated var tools: [ToolDefinition] { [] }

    init(
        providerDisplayName: String,
        remoteNamesByExposedName: [String: String],
        client: any MCPClientServing,
        approvalRequester: (any WorkspaceApprovalRequesting)?
    ) {
        self.providerDisplayName = providerDisplayName
        self.remoteNamesByExposedName = remoteNamesByExposedName
        self.client = client
        self.approvalRequester = approvalRequester
    }

    deinit {
        let client = client
        Task { await client.close() }
    }

    func execute(_ call: ToolCall) async throws -> AgentToolResult {
        guard let remoteName = remoteNamesByExposedName[call.function.name] else {
            return failure(call, "Unknown MCP tool: \(call.function.name)")
        }
        guard let approvalRequester else {
            return failure(call, "External tool approval is unavailable.")
        }

        let arguments: [String: JSONValue]
        do {
            arguments = try decodeArguments(call.function.arguments)
        } catch {
            return failure(call, MCPToolProviderError.invalidArguments.localizedDescription)
        }
        let preview = prettyArguments(arguments)
        let decision = try await approvalRequester.requestApproval(
            call: call,
            payload: .externalTool(
                ExternalToolProposal(
                    providerDisplayName: providerDisplayName,
                    toolName: remoteName,
                    argumentsPreview: preview
                )
            )
        )
        guard decision == .approve else {
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Rejected by user. The MCP tool was not called.",
                isSuccess: false,
                approvalState: .rejected
            )
        }

        do {
            let response = try await client.callTool(name: remoteName, arguments: arguments)
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: AgentMessageProjection.capToolOutput(response.content),
                isSuccess: !response.isError,
                approvalState: .approved
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "MCP tool call failed.",
                isSuccess: false,
                approvalState: .failed
            )
        }
    }

    private func decodeArguments(_ raw: String) throws -> [String: JSONValue] {
        guard let data = raw.data(using: .utf8),
              case .object(let object) = try JSONDecoder().decode(JSONValue.self, from: data) else {
            throw MCPToolProviderError.invalidArguments
        }
        return object
    }

    private func prettyArguments(_ arguments: [String: JSONValue]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(JSONValue.object(arguments)) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private func failure(_ call: ToolCall, _ content: String) -> AgentToolResult {
        AgentToolResult(
            callId: call.id,
            toolName: call.function.name,
            content: content,
            isSuccess: false
        )
    }
}
