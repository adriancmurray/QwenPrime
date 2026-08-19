import Foundation
import QwenPrimeCommandCore
import QwenPrimeCommandProtocol

/// Workspace tools with read operations and resumable, explicitly approved text mutations.
public struct WorkspaceToolBroker: Sendable {
    public let readBroker: ReadOnlyWorkspaceToolBroker
    public let mutationService: WorkspaceMutationService
    public let approvalRequester: (any WorkspaceApprovalRequesting)?
    public let commandExecutor: (any WorkspaceCommandExecuting)?

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

    public static let applyChangesDefinition = ToolDefinition(
        type: "function",
        function: .init(
            name: "workspace_apply_changes",
            description: "Propose up to eight exact UTF-8 text replacements across existing files as one combined review. Every old text must match exactly once, and no file changes until the user approves the combined diff.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "changes": .object([
                        "type": .string("array"),
                        "maxItems": .number(Double(WorkspaceMutationService.maxChangeSetSize)),
                        "items": .object([
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
                    ])
                ]),
                "required": .array([.string("changes")])
            ])
        )
    )

    public static let processRunDefinition = ToolDefinition(
        type: "function",
        function: .init(
            name: "workspace_process_run",
            description: "Run an argv-only process inside the authorized workspace through the sandboxed process helper after explicit user approval. The process is workspace-confined, network-disabled, time-bounded, and output-bounded. No shell parsing is performed by Qwen Prime.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "command": .object([
                        "type": .string("string"),
                        "description": .string("Executable name or workspace-relative executable path.")
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

    public static let processStartDefinition = ToolDefinition(
        type: "function",
        function: .init(
            name: "workspace_process_start",
            description: "Start a supervised argv-only process inside the authorized workspace after explicit user approval. Returns a process handle for later status and stop calls.",
            parameters: processRunDefinition.function.parameters
        )
    )

    public static let processStatusDefinition = ToolDefinition(
        type: "function",
        function: .init(
            name: "workspace_process_status",
            description: "Read the current state and bounded output of a process previously started by Qwen Prime.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "process_id": .object([
                        "type": .string("string"),
                        "description": .string("Process handle returned by workspace_process_start.")
                    ])
                ]),
                "required": .array([.string("process_id")])
            ])
        )
    )

    public static let processStopDefinition = ToolDefinition(
        type: "function",
        function: .init(
            name: "workspace_process_stop",
            description: "Stop a supervised workspace process after explicit user approval.",
            parameters: processStatusDefinition.function.parameters
        )
    )

    public var tools: [ToolDefinition] {
        guard approvalRequester != nil else { return readBroker.tools }
        var definitions = readBroker.tools + [
            Self.writeFileDefinition,
            Self.applyPatchDefinition,
            Self.applyChangesDefinition
        ]
        if commandExecutor != nil {
            definitions.append(Self.processRunDefinition)
            definitions.append(Self.processStartDefinition)
            definitions.append(Self.processStatusDefinition)
            definitions.append(Self.processStopDefinition)
        }
        return definitions
    }

    public var providerRegistration: AgentToolProviderRegistration {
        let readOnlyToolNames: Set<String> = [
            "workspace_list_directory",
            "workspace_read_file",
            "workspace_find_files",
            "workspace_search_text",
            "workspace_process_status"
        ]
        return AgentToolProviderRegistration(
            id: "workspace",
            displayName: "Workspace",
            tools: tools.map { definition in
                AgentToolRegistration(
                    definition: definition,
                    authorization: readOnlyToolNames.contains(definition.function.name)
                        ? .readOnly
                        : .userApproval
                )
            },
            executor: self
        )
    }

    public init(
        readService: ReadOnlyWorkspaceService,
        mutationService: WorkspaceMutationService,
        approvalRequester: (any WorkspaceApprovalRequesting)? = nil,
        commandExecutor: (any WorkspaceCommandExecuting)? = nil
    ) {
        self.readBroker = ReadOnlyWorkspaceToolBroker(service: readService)
        self.mutationService = mutationService
        self.approvalRequester = approvalRequester
        self.commandExecutor = commandExecutor
    }

    public func execute(_ call: ToolCall) async throws -> AgentToolResult {
        switch call.function.name {
        case "workspace_write_file":
            return try await executeWrite(call)
        case "workspace_apply_patch":
            return try await executePatch(call)
        case "workspace_apply_changes":
            return try await executeChanges(call)
        case "workspace_process_run":
            return try await executeCommand(call)
        case "workspace_process_start":
            return try await executeProcessStart(call)
        case "workspace_process_status":
            return try await executeProcessStatus(call)
        case "workspace_process_stop":
            return try await executeProcessStop(call)
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

    private func executeChanges(_ call: ToolCall) async throws -> AgentToolResult {
        do {
            let arguments = try decodeArguments(call)
            let changeSet = try await mutationService.prepareChangeSet(
                replacements: try requiredReplacements("changes", in: arguments)
            )
            return try await reviewAndExecute(call: call, changeSet: changeSet)
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

    private func executeProcessStart(_ call: ToolCall) async throws -> AgentToolResult {
        do {
            guard let approvalRequester, let commandExecutor else {
                return AgentToolResult(
                    callId: call.id,
                    toolName: call.function.name,
                    content: "Sandboxed process execution is unavailable.",
                    isSuccess: false
                )
            }
            let arguments = try decodeArguments(call)
            let command = try requiredString("command", in: arguments)
            let argv = try requiredStringArray("arguments", in: arguments)
            let workingDirectory = try optionalString("working_directory", in: arguments) ?? ""
            try WorkspaceCommandPolicy.validate(command: command, arguments: argv)
            try validateRelativeWorkingDirectory(workingDirectory)
            let proposal = try await commandExecutor.prepare(WorkspaceCommandProposal(
                command: command,
                arguments: argv,
                workingDirectory: workingDirectory
            ))
            let decision = try await approvalRequester.requestApproval(
                call: call,
                payload: .command(proposal)
            )
            guard decision == .approve else {
                return rejectedCommandResult(call: call, proposal: proposal)
            }
            return try processResult(
                call: call,
                snapshot: try await commandExecutor.start(proposal),
                approvalState: .approved,
                proposal: proposal
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return failureResult(call: call, error: error)
        }
    }

    private func executeProcessStatus(_ call: ToolCall) async throws -> AgentToolResult {
        do {
            guard let commandExecutor else {
                return AgentToolResult(
                    callId: call.id,
                    toolName: call.function.name,
                    content: "Sandboxed process execution is unavailable.",
                    isSuccess: false
                )
            }
            let arguments = try decodeArguments(call)
            let id = try processID(in: arguments)
            return try processResult(
                call: call,
                snapshot: try await commandExecutor.status(id: id),
                approvalState: nil,
                proposal: nil
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return failureResult(call: call, error: error)
        }
    }

    private func executeProcessStop(_ call: ToolCall) async throws -> AgentToolResult {
        do {
            guard let approvalRequester, let commandExecutor else {
                return AgentToolResult(
                    callId: call.id,
                    toolName: call.function.name,
                    content: "Sandboxed process execution is unavailable.",
                    isSuccess: false
                )
            }
            let id = try processID(in: decodeArguments(call))
            let proposal = WorkspaceCommandProposal(
                command: "stop-process",
                arguments: [id.uuidString]
            )
            let decision = try await approvalRequester.requestApproval(
                call: call,
                payload: .command(proposal)
            )
            guard decision == .approve else {
                return rejectedCommandResult(call: call, proposal: proposal)
            }
            return try processResult(
                call: call,
                snapshot: try await commandExecutor.stop(id: id),
                approvalState: .approved,
                proposal: proposal
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
            return rejectedCommandResult(call: call, proposal: proposal)
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

    private func rejectedCommandResult(
        call: ToolCall,
        proposal: WorkspaceCommandProposal
    ) -> AgentToolResult {
        AgentToolResult(
            callId: call.id,
            toolName: call.function.name,
            content: "Rejected by user. The command was not executed.",
            isSuccess: false,
            approvalState: .rejected,
            commandProposal: proposal
        )
    }

    private func processResult(
        call: ToolCall,
        snapshot: WorkspaceProcessSnapshot,
        approvalState: ToolApprovalState?,
        proposal: WorkspaceCommandProposal?
    ) throws -> AgentToolResult {
        let sanitized = sanitizeProcessSnapshot(snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return AgentToolResult(
            callId: call.id,
            toolName: call.function.name,
            content: String(decoding: try encoder.encode(sanitized), as: UTF8.self),
            isSuccess: sanitized.state != .failed,
            approvalState: approvalState,
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

    private func reviewAndExecute(
        call: ToolCall,
        changeSet: WorkspaceMutationChangeSet
    ) async throws -> AgentToolResult {
        guard let approvalRequester else {
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Workspace mutation approval is unavailable.",
                isSuccess: false
            )
        }

        let proposal = changeSet.reviewProposal
        let decision = try await approvalRequester.requestApproval(
            call: call,
            payload: .mutation(proposal)
        )
        guard decision == .approve else {
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Rejected by user. The workspace was not modified.",
                isSuccess: false,
                mutationProposal: proposal,
                approvalState: .rejected
            )
        }

        do {
            try await mutationService.apply(changeSet)
            return AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Applied \(changeSet.changes.count) reviewed changes across \(proposal.relativePath).",
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

    private func processID(in arguments: [String: Any]) throws -> UUID {
        let value = try requiredString("process_id", in: arguments)
        guard let id = UUID(uuidString: value) else {
            throw WorkspaceToolArgumentError.invalidType("process_id")
        }
        return id
    }

    private func requiredReplacements(
        _ key: String,
        in arguments: [String: Any]
    ) throws -> [WorkspaceTextReplacement] {
        guard let value = arguments[key] else {
            throw WorkspaceToolArgumentError.missing(key)
        }
        guard let array = value as? [Any] else {
            throw WorkspaceToolArgumentError.invalidType(key)
        }
        return try array.map { value in
            guard let object = value as? [String: Any] else {
                throw WorkspaceToolArgumentError.invalidType(key)
            }
            return WorkspaceTextReplacement(
                path: try requiredString("path", in: object),
                oldText: try requiredString("old_text", in: object),
                newText: try requiredString("new_text", in: object)
            )
        }
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

    private func sanitizeProcessSnapshot(
        _ snapshot: WorkspaceProcessSnapshot
    ) -> WorkspaceProcessSnapshot {
        WorkspaceProcessSnapshot(
            id: snapshot.id,
            state: snapshot.state,
            result: snapshot.result.map(sanitizeCommandResponse),
            errorMessage: snapshot.errorMessage.map(sanitizeCommandOutput)
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
