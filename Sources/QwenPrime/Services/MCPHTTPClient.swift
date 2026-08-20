import Foundation
import MCP

public actor MCPHTTPClient: MCPClientServing {
    public static let maxDiscoveredTools = 128

    private let client: MCP.Client

    private init(client: MCP.Client) {
        self.client = client
    }

    public static func connect(
        configuration: MCPServerConfiguration
    ) async throws -> MCPHTTPClient {
        let client = MCP.Client(
            name: "QwenPrime",
            version: AppVersionPresentation.shortVersion,
            capabilities: .init(),
            configuration: .strict
        )
        let transport = MCP.HTTPClientTransport(
            endpoint: configuration.endpoint,
            streaming: true
        )
        try await client.connect(transport: transport)
        return MCPHTTPClient(client: client)
    }

    public func listTools() async throws -> [MCPRemoteTool] {
        var discovered: [MCPRemoteTool] = []
        var cursor: String?
        var seenCursors = Set<String>()

        repeat {
            let page = try await client.listTools(cursor: cursor)
            for tool in page.tools {
                guard discovered.count < Self.maxDiscoveredTools else { return discovered }
                discovered.append(
                    MCPRemoteTool(
                        name: tool.name,
                        description: tool.description,
                        inputSchema: MCPValueBridge.jsonValue(from: tool.inputSchema)
                    )
                )
            }
            cursor = page.nextCursor
            if let cursor, !seenCursors.insert(cursor).inserted { break }
        } while cursor != nil && discovered.count < Self.maxDiscoveredTools

        return discovered
    }

    public func callTool(
        name: String,
        arguments: [String: JSONValue]
    ) async throws -> MCPRemoteToolResult {
        let response = try await client.callTool(
            name: name,
            arguments: MCPValueBridge.arguments(from: arguments)
        )
        let text = response.content.map(Self.render).joined(separator: "\n")
        return MCPRemoteToolResult(
            content: text.isEmpty ? "MCP tool returned no content." : text,
            isError: response.isError == true
        )
    }

    public func close() async {
        await client.disconnect()
    }

    private static func render(_ content: MCP.Tool.Content) -> String {
        switch content {
        case .text(let text, _, _):
            return text
        case .image(_, let mimeType, _, _):
            return "[MCP image result: \(mimeType)]"
        case .audio(_, let mimeType, _, _):
            return "[MCP audio result: \(mimeType)]"
        case .resource:
            return "[MCP embedded resource]"
        case .resourceLink(let uri, let name, let title, _, let mimeType, _):
            let label = title ?? name
            let type = mimeType.map { " (\($0))" } ?? ""
            return "[MCP resource: \(label) — \(uri)\(type)]"
        }
    }
}

enum MCPValueBridge {
    static func jsonValue(from value: MCP.Value) -> JSONValue {
        switch value {
        case .null:
            return .null
        case .bool(let value):
            return .bool(value)
        case .int(let value):
            return .number(Double(value))
        case .double(let value):
            return .number(value)
        case .string(let value):
            return .string(value)
        case .data:
            return .string(value.description)
        case .array(let values):
            return .array(values.map(jsonValue(from:)))
        case .object(let values):
            return .object(values.mapValues(jsonValue(from:)))
        }
    }

    static func arguments(from values: [String: JSONValue]) -> [String: MCP.Value] {
        values.mapValues(mcpValue(from:))
    }

    private static func mcpValue(from value: JSONValue) -> MCP.Value {
        switch value {
        case .null:
            return .null
        case .bool(let value):
            return .bool(value)
        case .number(let value):
            if value.isFinite,
               value.rounded() == value,
               value >= Double(Int.min),
               value <= Double(Int.max) {
                return .int(Int(value))
            }
            return .double(value)
        case .string(let value):
            return .string(value)
        case .array(let values):
            return .array(values.map(mcpValue(from:)))
        case .object(let values):
            return .object(values.mapValues(mcpValue(from:)))
        }
    }
}
