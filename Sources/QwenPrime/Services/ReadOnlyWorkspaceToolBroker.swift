import Foundation

/// Read-only workspace tool broker exposing bounded listing and file reading tools.
public struct ReadOnlyWorkspaceToolBroker: Sendable {
    public let service: ReadOnlyWorkspaceService
    private let pathSanitizer: WorkspacePathSanitizer

    public static let listDirectoryDefinition = ToolDefinition(
        type: "function",
        function: ToolDefinition.FunctionDefinition(
            name: ToolName.workspaceListDirectory,
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
            name: ToolName.workspaceReadFile,
            description: "Read the UTF-8 text content of a file in the workspace at the specified relative path.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Relative file path from the workspace root.")
                    ]),
                    "start_line": .object([
                        "type": .string("integer"),
                        "description": .string("Optional 1-based inclusive first line.")
                    ]),
                    "end_line": .object([
                        "type": .string("integer"),
                        "description": .string("Optional 1-based inclusive final line.")
                    ])
                ]),
                "required": .array([.string("path")])
            ])
        )
    )

    public static let findFilesDefinition = ToolDefinition(
        type: "function",
        function: .init(
            name: ToolName.workspaceFindFiles,
            description: "Recursively find files whose names contain a literal query, within bounded workspace limits.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("Literal filename query, between 1 and 256 UTF-8 bytes.")
                    ]),
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Optional relative directory to search from.")
                    ]),
                    "case_sensitive": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether filename matching is case-sensitive. Defaults to false.")
                    ])
                ]),
                "required": .array([.string("query")])
            ])
        )
    )

    public static let searchTextDefinition = ToolDefinition(
        type: "function",
        function: .init(
            name: ToolName.workspaceSearchText,
            description: "Recursively search bounded UTF-8 workspace text for a literal query and return matching paths, line numbers, and lines.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("Literal text query, between 1 and 256 UTF-8 bytes.")
                    ]),
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Optional relative directory to search from.")
                    ]),
                    "case_sensitive": .object([
                        "type": .string("boolean"),
                        "description": .string("Whether text matching is case-sensitive. Defaults to true.")
                    ])
                ]),
                "required": .array([.string("query")])
            ])
        )
    )

    public let tools: [ToolDefinition]

    public init(service: ReadOnlyWorkspaceService) {
        self.service = service
        self.pathSanitizer = WorkspacePathSanitizer(
            workspaceRoot: service.rootURL
        )
        self.tools = [
            Self.listDirectoryDefinition,
            Self.readFileDefinition,
            Self.findFilesDefinition,
            Self.searchTextDefinition
        ]
    }

    /// Executes a tool call within the read-only workspace boundary.
    public func execute(_ call: ToolCall) async throws -> AgentToolResult {
        try Task.checkCancellation()

        switch call.function.name {
        case ToolName.workspaceListDirectory:
            return try await executeListDirectory(call)
        case ToolName.workspaceReadFile:
            return try await executeReadFile(call)
        case ToolName.workspaceFindFiles:
            return try await executeFindFiles(call)
        case ToolName.workspaceSearchText:
            return try await executeSearchText(call)
        default:
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Unknown tool: \(call.function.name)",
                isSuccess: false
            )
        }
    }

    private func executeFindFiles(_ call: ToolCall) async throws -> AgentToolResult {
        try await executeSearch(call) { query, path, caseSensitive in
            try await service.findFiles(
                query: query,
                relativePath: path,
                caseSensitive: caseSensitive ?? false
            )
        }
    }

    private func executeSearchText(_ call: ToolCall) async throws -> AgentToolResult {
        try await executeSearch(call) { query, path, caseSensitive in
            try await service.searchText(
                query: query,
                relativePath: path,
                caseSensitive: caseSensitive ?? true
            )
        }
    }

    private func executeSearch<Result: Encodable & Sendable>(
        _ call: ToolCall,
        operation: (String, String?, Bool?) async throws -> Result
    ) async throws -> AgentToolResult {
        do {
            let dict = try decodeObject(call.function.arguments)
            guard let query = dict["query"] as? String else {
                return argumentFailure(call, "Missing or invalid required argument: query")
            }
            let path = try optionalString("path", in: dict)
            let caseSensitive = try optionalBool("case_sensitive", in: dict)
            let result = try await operation(query, path, caseSensitive)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: String(decoding: try encoder.encode(result), as: UTF8.self),
                isSuccess: true
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return argumentFailure(
                call,
                pathSanitizer.sanitize(error.localizedDescription)
            )
        }
    }

    private func decodeObject(_ arguments: String) throws -> [String: Any] {
        guard let data = arguments.data(using: .utf8), !data.isEmpty else {
            throw WorkspaceToolArgumentError.invalid("expected non-empty JSON string")
        }
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let dict = object as? [String: Any] else {
            throw WorkspaceToolArgumentError.invalid("expected JSON object")
        }
        return dict
    }

    private func optionalString(_ key: String, in dict: [String: Any]) throws -> String? {
        guard let value = dict[key], !(value is NSNull) else { return nil }
        guard let string = value as? String else {
            throw WorkspaceToolArgumentError.invalid("expected string for '\(key)'")
        }
        return string
    }

    private func optionalBool(_ key: String, in dict: [String: Any]) throws -> Bool? {
        guard let value = dict[key], !(value is NSNull) else { return nil }
        guard let bool = value as? Bool else {
            throw WorkspaceToolArgumentError.invalid("expected boolean for '\(key)'")
        }
        return bool
    }

    private func argumentFailure(_ call: ToolCall, _ message: String) -> AgentToolResult {
        AgentToolResult(
            callId: call.id,
            toolName: call.function.name,
            content: message,
            isSuccess: false
        )
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
                content: pathSanitizer.sanitize(error.localizedDescription),
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

        let startLine: Int?
        if let value = dict["start_line"], !(value is NSNull) {
            guard !(value is Bool), let line = value as? Int else {
                return AgentToolResult(
                    callId: call.id,
                    toolName: call.function.name,
                    content: "Invalid argument type for 'start_line': expected integer",
                    isSuccess: false
                )
            }
            startLine = line
        } else {
            startLine = nil
        }

        let endLine: Int?
        if let value = dict["end_line"], !(value is NSNull) {
            guard !(value is Bool), let line = value as? Int else {
                return AgentToolResult(
                    callId: call.id,
                    toolName: call.function.name,
                    content: "Invalid argument type for 'end_line': expected integer",
                    isSuccess: false
                )
            }
            endLine = line
        } else {
            endLine = nil
        }

        do {
            let fileRead = try await service.readFile(
                relativePath: pathString,
                startLine: startLine,
                endLine: endLine
            )
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
                content: pathSanitizer.sanitize(error.localizedDescription),
                isSuccess: false
            )
        }
    }

}

private enum WorkspaceToolArgumentError: Error, LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message):
            return "Invalid arguments: \(message)"
        }
    }
}
