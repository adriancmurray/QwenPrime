import Foundation

/// Read-only workspace tool broker exposing bounded listing and file reading tools.
public struct ReadOnlyWorkspaceToolBroker: Sendable {
    public let service: ReadOnlyWorkspaceService

    public static let listDirectoryDefinition = ToolDefinition(
        type: "function",
        function: ToolDefinition.FunctionDefinition(
            name: "workspace_list_directory",
            description: "List files and directories in the workspace at the specified relative path, or root if omitted.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Optional relative directory path from the workspace root. Defaults to the workspace root if omitted.")
                    ])
                ]),
                "required": .array([])
            ])
        )
    )

    public static let readFileDefinition = ToolDefinition(
        type: "function",
        function: ToolDefinition.FunctionDefinition(
            name: "workspace_read_file",
            description: "Read the UTF-8 text content of a file in the workspace at the specified relative path.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Relative file path from the workspace root.")
                    ])
                ]),
                "required": .array([.string("path")])
            ])
        )
    )

    public let tools: [ToolDefinition]

    public init(service: ReadOnlyWorkspaceService) {
        self.service = service
        self.tools = [
            Self.listDirectoryDefinition,
            Self.readFileDefinition
        ]
    }

    /// Executes a tool call within the read-only workspace boundary.
    public func execute(_ call: ToolCall) async throws -> AgentToolResult {
        try Task.checkCancellation()

        switch call.function.name {
        case "workspace_list_directory":
            return try await executeListDirectory(call)
        case "workspace_read_file":
            return try await executeReadFile(call)
        default:
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Unknown tool: \(call.function.name)",
                isSuccess: false
            )
        }
    }

    private func executeListDirectory(_ call: ToolCall) async throws -> AgentToolResult {
        let arguments = call.function.arguments
        guard let data = arguments.data(using: .utf8), !data.isEmpty else {
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Invalid arguments: expected non-empty JSON string",
                isSuccess: false
            )
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Malformed arguments JSON: \(error.localizedDescription)",
                isSuccess: false
            )
        }

        guard let dict = jsonObject as? [String: Any] else {
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Invalid arguments: expected JSON object",
                isSuccess: false
            )
        }

        let relativePath: String?
        if let pathValue = dict["path"] {
            if pathValue is NSNull {
                relativePath = nil
            } else if let pathString = pathValue as? String {
                relativePath = pathString
            } else {
                return AgentToolResult(
                    callId: call.id,
                    toolName: call.function.name,
                    content: "Invalid argument type for 'path': expected string",
                    isSuccess: false
                )
            }
        } else {
            relativePath = nil
        }

        do {
            let listing = try await service.listDirectory(relativePath: relativePath)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let encodedData = try encoder.encode(listing)
            let content = String(decoding: encodedData, as: UTF8.self)
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: content,
                isSuccess: true
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: sanitize(error.localizedDescription),
                isSuccess: false
            )
        }
    }

    private func executeReadFile(_ call: ToolCall) async throws -> AgentToolResult {
        let arguments = call.function.arguments
        guard let data = arguments.data(using: .utf8), !data.isEmpty else {
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Invalid arguments: expected non-empty JSON string",
                isSuccess: false
            )
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Malformed arguments JSON: \(error.localizedDescription)",
                isSuccess: false
            )
        }

        guard let dict = jsonObject as? [String: Any] else {
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Invalid arguments: expected JSON object",
                isSuccess: false
            )
        }

        guard let pathValue = dict["path"] else {
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Missing required argument: path",
                isSuccess: false
            )
        }

        guard let pathString = pathValue as? String else {
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Invalid argument type for 'path': expected string",
                isSuccess: false
            )
        }

        do {
            let fileRead = try await service.readFile(relativePath: pathString)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let encodedData = try encoder.encode(fileRead)
            let content = String(decoding: encodedData, as: UTF8.self)
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: content,
                isSuccess: true
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: sanitize(error.localizedDescription),
                isSuccess: false
            )
        }
    }

    private func sanitize(_ text: String) -> String {
        var result = text
        let rootPath = service.rootURL.path
        if !rootPath.isEmpty {
            result = result.replacingOccurrences(of: rootPath, with: "<workspace_root>")
        }
        let standardizedPath = service.rootURL.standardized.path
        if !standardizedPath.isEmpty && standardizedPath != rootPath {
            result = result.replacingOccurrences(of: standardizedPath, with: "<workspace_root>")
        }
        let realPath = service.rootURL.resolvingSymlinksInPath().path
        if !realPath.isEmpty && realPath != rootPath && realPath != standardizedPath {
            result = result.replacingOccurrences(of: realPath, with: "<workspace_root>")
        }
        return result
    }
}
