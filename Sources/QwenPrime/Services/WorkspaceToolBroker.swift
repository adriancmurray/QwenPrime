import Foundation
import QwenPrimeCommandCore
import QwenPrimeCommandProtocol

/// Workspace tools with read operations and resumable, explicitly approved text mutations.
public struct WorkspaceToolBroker: Sendable {
    public let readBroker: ReadOnlyWorkspaceToolBroker
    public let mutationService: WorkspaceMutationService
    public let approvalRequester: (any WorkspaceApprovalRequesting)?
    public let commandExecutor: (any WorkspaceCommandExecuting)?
    public let taskExecutionEnabled: Bool

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

    public static let runCommandDefinition = ToolDefinition(
        type: "function",
        function: .init(
            name: "workspace_run_command",
            description: "Run a bounded inspection command in the workspace through the sandboxed command helper after explicit user approval. Supported commands: pwd, flag-only ls, and fixed-form git log/rev-parse metadata inspection.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "command": .object([
                        "type": .string("string"),
                        "description": .string("One of: pwd, ls, git.")
                    ]),
                    "arguments": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Argument vector. Shell expressions are not supported.")
                    ]),
                    "working_directory": .object([
                        "type": .string("string"),
                        "description": .string("Optional relative working directory inside the workspace.")
                    ])
                ]),
                "required": .array([.string("command"), .string("arguments")])
            ])
        )
    )

    public static let runTaskDefinition = ToolDefinition(
        type: "function",
        function: .init(
            name: "workspace_run_task",
            description: "Run an approved, sandboxed build or test task with isolated temporary outputs. Supported tasks: swift_build and swift_test. The runner is offline, so packages must be self-contained without unresolved remote dependencies. This is not a shell.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "task": .object([
                        "type": .string("string"),
                        "enum": .array([.string("swift_build"), .string("swift_test")])
                    ]),
                    "filter": .object([
                        "type": .string("string"),
                        "description": .string("Optional Swift test filter. Valid only for swift_test.")
                    ]),
                    "working_directory": .object([
                        "type": .string("string"),
                        "description": .string("Optional relative package directory inside the workspace.")
                    ])
                ]),
                "required": .array([.string("task")])
            ])
        )
    )

    public var tools: [ToolDefinition] {
        guard approvalRequester != nil else { return readBroker.tools }
        var definitions = readBroker.tools + [Self.writeFileDefinition, Self.applyPatchDefinition]
        if commandExecutor != nil {
            definitions.append(Self.runCommandDefinition)
            if taskExecutionEnabled {
                definitions.append(Self.runTaskDefinition)
            }
        }
        return definitions
    }

    public init(
        readService: ReadOnlyWorkspaceService,
        mutationService: WorkspaceMutationService,
        approvalRequester: (any WorkspaceApprovalRequesting)? = nil,
        commandExecutor: (any WorkspaceCommandExecuting)? = nil,
        taskExecutionEnabled: Bool = false
    ) {
        self.readBroker = ReadOnlyWorkspaceToolBroker(service: readService)
        self.mutationService = mutationService
        self.approvalRequester = approvalRequester
        self.commandExecutor = commandExecutor
        self.taskExecutionEnabled = taskExecutionEnabled
    }

    public func execute(_ call: ToolCall) async throws -> AgentToolResult {
        switch call.function.name {
        case "workspace_write_file":
            return try await executeWrite(call)
        case "workspace_apply_patch":
            return try await executePatch(call)
        case "workspace_run_command":
            return try await executeCommand(call)
        case "workspace_run_task":
            if taskExecutionEnabled {
                return try await executeTask(call)
            }
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Build and test task execution is not enabled in this build.",
                isSuccess: false
            )
        default:
            return try await readBroker.execute(call)
        }
    }

    private func executeWrite(_ call: ToolCall) async throws -> AgentToolResult {
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
            return try await reviewAndExecute(call: call, proposal: proposal)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return failureResult(call: call, error: error)
        }
    }

    private func executePatch(_ call: ToolCall) async throws -> AgentToolResult {
        do {
            let arguments = try decodeArguments(call)
            let proposal = try await mutationService.preparePatch(
                relativePath: try requiredString("path", in: arguments),
                oldText: try requiredString("old_text", in: arguments),
                newText: try requiredString("new_text", in: arguments)
            )
            return try await reviewAndExecute(call: call, proposal: proposal)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return failureResult(call: call, error: error)
        }
    }

    private func executeCommand(_ call: ToolCall) async throws -> AgentToolResult {
        do {
            guard let approvalRequester, let commandExecutor else {
                return AgentToolResult(
                    callId: call.id,
                    toolName: call.function.name,
                    content: "Sandboxed command execution is unavailable.",
                    isSuccess: false
                )
            }
            let arguments = try decodeArguments(call)
            let command = try requiredString("command", in: arguments)
            guard ["pwd", "ls", "git"].contains(command) else {
                throw CommandPolicyError.unsupportedCommand(command)
            }
            let argv = try requiredStringArray("arguments", in: arguments)
            let workingDirectory = try optionalString("working_directory", in: arguments) ?? ""
            try WorkspaceCommandPolicy.validate(command: command, arguments: argv)
            try validateRelativeWorkingDirectory(workingDirectory)
            let initialProposal = WorkspaceCommandProposal(
                command: command,
                arguments: argv,
                workingDirectory: workingDirectory
            )
            return try await reviewAndExecuteCommand(
                call: call,
                initialProposal: initialProposal,
                approvalRequester: approvalRequester,
                commandExecutor: commandExecutor
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return failureResult(call: call, error: error)
        }
    }

    private func executeTask(_ call: ToolCall) async throws -> AgentToolResult {
        do {
            guard let approvalRequester, let commandExecutor else {
                return AgentToolResult(
                    callId: call.id,
                    toolName: call.function.name,
                    content: "Sandboxed task execution is unavailable.",
                    isSuccess: false
                )
            }
            let arguments = try decodeArguments(call)
            let task = try requiredString("task", in: arguments)
            let filter = try optionalString("filter", in: arguments)
            let workingDirectory = try optionalString("working_directory", in: arguments) ?? ""
            try validateRelativeWorkingDirectory(workingDirectory)

            let taskArguments: [String]
            switch task {
            case "swift_build":
                guard filter == nil else {
                    throw CommandPolicyError.invalidArguments("filter is valid only for swift_test")
                }
                taskArguments = ["build"]
            case "swift_test":
                taskArguments = filter.map { ["test", "--filter", $0] } ?? ["test"]
            default:
                throw CommandPolicyError.invalidArguments("unsupported task")
            }
            try WorkspaceCommandPolicy.validate(
                command: "swift",
                arguments: taskArguments
            )
            return try await reviewAndExecuteCommand(
                call: call,
                initialProposal: WorkspaceCommandProposal(
                    command: "swift",
                    arguments: taskArguments,
                    workingDirectory: workingDirectory
                ),
                approvalRequester: approvalRequester,
                commandExecutor: commandExecutor
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return failureResult(call: call, error: error)
        }
    }

    private func reviewAndExecuteCommand(
        call: ToolCall,
        initialProposal: WorkspaceCommandProposal,
        approvalRequester: any WorkspaceApprovalRequesting,
        commandExecutor: any WorkspaceCommandExecuting
    ) async throws -> AgentToolResult {
        let proposal = try await commandExecutor.prepare(initialProposal)
        let decision = try await approvalRequester.requestApproval(
            call: call,
            payload: .command(proposal)
        )
        guard decision == .approve else {
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Rejected by user. The command was not executed.",
                isSuccess: false,
                approvalState: .rejected,
                commandProposal: proposal
            )
        }

        let response = sanitizeCommandResponse(
            try await commandExecutor.execute(proposal)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return AgentToolResult(
            callId: call.id,
            toolName: call.function.name,
            content: String(decoding: try encoder.encode(response), as: UTF8.self),
            isSuccess: response.isSuccess,
            approvalState: .approved,
            commandProposal: proposal
        )
    }

    private func reviewAndExecute(
        call: ToolCall,
        proposal: WorkspaceMutationProposal
    ) async throws -> AgentToolResult {
        guard let approvalRequester else {
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Workspace mutation approval is unavailable.",
                isSuccess: false
            )
        }

        let decision = try await approvalRequester.requestApproval(
            call: call,
            payload: .mutation(proposal)
        )
        switch decision {
        case .approve:
            do {
                try await mutationService.apply(proposal)
                return AgentToolResult(
                    callId: call.id,
                    toolName: call.function.name,
                    content: "Applied to \(proposal.relativePath).",
                    isSuccess: true,
                    mutationProposal: proposal,
                    approvalState: .approved
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return AgentToolResult(
                    callId: call.id,
                    toolName: call.function.name,
                    content: sanitize(error.localizedDescription),
                    isSuccess: false,
                    mutationProposal: proposal,
                    approvalState: .failed
                )
            }
        case .reject:
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Rejected by user. The workspace was not modified.",
                isSuccess: false,
                mutationProposal: proposal,
                approvalState: .rejected
            )
        }
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

    private func optionalString(_ key: String, in arguments: [String: Any]) throws -> String? {
        guard let value = arguments[key], !(value is NSNull) else { return nil }
        guard let string = value as? String else {
            throw WorkspaceToolArgumentError.invalidType(key)
        }
        return string
    }

    private func requiredStringArray(_ key: String, in arguments: [String: Any]) throws -> [String] {
        guard let value = arguments[key] else {
            throw WorkspaceToolArgumentError.missing(key)
        }
        guard let array = value as? [Any], array.allSatisfy({ $0 is String }) else {
            throw WorkspaceToolArgumentError.invalidType(key)
        }
        return array.compactMap { $0 as? String }
    }

    private func validateRelativeWorkingDirectory(_ path: String) throws {
        guard !path.hasPrefix("/"), !path.utf8.contains(0),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains("..") else {
            throw CommandPolicyError.pathEscape(path)
        }
    }

    private func sanitize(_ text: String) -> String {
        text.replacingOccurrences(
            of: mutationService.readService.rootURL.path,
            with: "<workspace_root>"
        )
    }

    private func sanitizeCommandResponse(
        _ response: CommandExecutionResponse
    ) -> CommandExecutionResponse {
        CommandExecutionResponse(
            id: response.id,
            exitCode: response.exitCode,
            stdout: sanitizeCommandOutput(response.stdout),
            stderr: sanitizeCommandOutput(response.stderr),
            outputTruncated: response.outputTruncated,
            timedOut: response.timedOut,
            cancelled: response.cancelled,
            durationSeconds: response.durationSeconds,
            errorMessage: response.errorMessage.map(sanitizeCommandOutput)
        )
    }

    private func sanitizeCommandOutput(_ text: String) -> String {
        let workspaceURL = mutationService.readService.rootURL
        let workspacePaths = [
            workspaceURL.path,
            workspaceURL.standardizedFileURL.path,
            workspaceURL.resolvingSymlinksInPath().path
        ].sorted { $0.count > $1.count }
        var result = text
        for path in workspacePaths where !path.isEmpty {
            result = result.replacingOccurrences(of: path, with: "<workspace_root>")
        }

        let temporaryURL = FileManager.default.temporaryDirectory
        let temporaryPaths = [
            temporaryURL.path,
            temporaryURL.standardizedFileURL.path,
            temporaryURL.resolvingSymlinksInPath().path
        ].sorted { $0.count > $1.count }
        for path in temporaryPaths where !path.isEmpty {
            result = result.replacingOccurrences(of: path, with: "<task_temp>")
        }
        return result
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
