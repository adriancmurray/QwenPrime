import Foundation

/// Workspace tools with read operations and mutation proposals that require later user approval.
public struct WorkspaceToolBroker: Sendable {
    public let readBroker: ReadOnlyWorkspaceToolBroker
    public let mutationService: WorkspaceMutationService

    public static let writeFileDefinition = ToolDefinition(
        type: "function",
        function: .init(
            name: "workspace_write_file",
            description: "Propose creating or replacing a UTF-8 text file. The user must review and approve the diff before the workspace changes.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Relative file path from the workspace root.")
                    ]),
                    "content": .object([
                        "type": .string("string"),
                        "description": .string("Complete proposed UTF-8 file content.")
                    ]),
                    "overwrite": .object([
                        "type": .string("boolean"),
                        "description": .string("Set true only when intentionally replacing an existing file.")
                    ])
                ]),
                "required": .array([.string("path"), .string("content")])
            ])
        )
    )

    public static let applyPatchDefinition = ToolDefinition(
        type: "function",
        function: .init(
            name: "workspace_apply_patch",
            description: "Propose one exact UTF-8 text replacement in an existing file. The old text must match exactly once, and the user must approve the diff.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Relative file path from the workspace root.")
                    ]),
                    "old_text": .object([
                        "type": .string("string"),
                        "description": .string("Exact existing text to replace; it must occur once.")
                    ]),
                    "new_text": .object([
                        "type": .string("string"),
                        "description": .string("Replacement text.")
                    ])
                ]),
                "required": .array([.string("path"), .string("old_text"), .string("new_text")])
            ])
        )
    )

    public var tools: [ToolDefinition] {
        readBroker.tools + [Self.writeFileDefinition, Self.applyPatchDefinition]
    }

    public init(
        readService: ReadOnlyWorkspaceService,
        mutationService: WorkspaceMutationService
    ) {
        self.readBroker = ReadOnlyWorkspaceToolBroker(service: readService)
        self.mutationService = mutationService
    }

    public func execute(_ call: ToolCall) async throws -> AgentToolResult {
        switch call.function.name {
        case "workspace_write_file":
            return try await proposeWrite(call)
        case "workspace_apply_patch":
            return try await proposePatch(call)
        default:
            return try await readBroker.execute(call)
        }
    }

    private func proposeWrite(_ call: ToolCall) async throws -> AgentToolResult {
        do {
            let arguments = try decodeArguments(call)
            let path = try requiredString("path", in: arguments)
            let content = try requiredString("content", in: arguments)
            let overwrite = try optionalBool("overwrite", in: arguments) ?? false
            let proposal = try await mutationService.prepareWrite(
                relativePath: path,
                content: content,
                overwrite: overwrite
            )
            return approvalResult(call: call, proposal: proposal)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return failureResult(call: call, error: error)
        }
    }

    private func proposePatch(_ call: ToolCall) async throws -> AgentToolResult {
        do {
            let arguments = try decodeArguments(call)
            let proposal = try await mutationService.preparePatch(
                relativePath: try requiredString("path", in: arguments),
                oldText: try requiredString("old_text", in: arguments),
                newText: try requiredString("new_text", in: arguments)
            )
            return approvalResult(call: call, proposal: proposal)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return failureResult(call: call, error: error)
        }
    }

    private func approvalResult(
        call: ToolCall,
        proposal: WorkspaceMutationProposal
    ) -> AgentToolResult {
        AgentToolResult(
            callId: call.id,
            toolName: call.function.name,
            content: "Change queued in the app review panel. The workspace is unchanged. Do not repeat the diff; briefly state that review is ready.",
            isSuccess: true,
            mutationProposal: proposal
        )
    }

    private func failureResult(call: ToolCall, error: Error) -> AgentToolResult {
        AgentToolResult(
            callId: call.id,
            toolName: call.function.name,
            content: sanitize(error.localizedDescription),
            isSuccess: false
        )
    }

    private func decodeArguments(_ call: ToolCall) throws -> [String: Any] {
        guard let data = call.function.arguments.data(using: .utf8),
              !data.isEmpty else {
            throw WorkspaceToolArgumentError.invalidJSON
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let arguments = object as? [String: Any] else {
            throw WorkspaceToolArgumentError.expectedObject
        }
        return arguments
    }

    private func requiredString(_ key: String, in arguments: [String: Any]) throws -> String {
        guard let value = arguments[key] else {
            throw WorkspaceToolArgumentError.missing(key)
        }
        guard let string = value as? String else {
            throw WorkspaceToolArgumentError.invalidType(key)
        }
        return string
    }

    private func optionalBool(_ key: String, in arguments: [String: Any]) throws -> Bool? {
        guard let value = arguments[key], !(value is NSNull) else { return nil }
        guard let bool = value as? Bool else {
            throw WorkspaceToolArgumentError.invalidType(key)
        }
        return bool
    }

    private func sanitize(_ text: String) -> String {
        text.replacingOccurrences(
            of: mutationService.readService.rootURL.path,
            with: "<workspace_root>"
        )
    }
}

extension WorkspaceToolBroker: AgentToolExecuting {}

private enum WorkspaceToolArgumentError: Error, LocalizedError {
    case invalidJSON
    case expectedObject
    case missing(String)
    case invalidType(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Invalid arguments: expected non-empty JSON."
        case .expectedObject:
            return "Invalid arguments: expected a JSON object."
        case .missing(let key):
            return "Missing required argument: \(key)"
        case .invalidType(let key):
            return "Invalid argument type for '\(key)'."
        }
    }
}
