import Foundation

public enum CommandResourceAccess: String, Sendable, Codable, Equatable, Hashable {
    case readOnly
}

public struct CommandResourceGrant: Sendable, Codable, Equatable, Hashable {
    public let path: String
    public let access: CommandResourceAccess

    public init(path: String, access: CommandResourceAccess) {
        self.path = path
        self.access = access
    }
}

public struct WorkspaceCommandProposal: Sendable, Codable, Equatable, Hashable {
    public let command: String
    public let arguments: [String]
    public let workingDirectory: String
    public let resourceGrants: [CommandResourceGrant]

    public init(
        command: String,
        arguments: [String],
        workingDirectory: String = "",
        resourceGrants: [CommandResourceGrant] = []
    ) {
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.resourceGrants = resourceGrants
    }

    public var preview: String {
        let renderedArguments = arguments.map(Self.quoteForDisplay).joined(separator: " ")
        let commandLine = renderedArguments.isEmpty ? command : "\(command) \(renderedArguments)"
        let directory = workingDirectory.isEmpty ? "." : workingDirectory
        var lines = ["$ \(commandLine)", "working directory: \(directory)"]
        if !resourceGrants.isEmpty {
            lines.append("Additional read-only access:")
            lines.append(contentsOf: resourceGrants.map { "- \($0.path)" })
        }
        return lines.joined(separator: "\n")
    }

    private static func quoteForDisplay(_ argument: String) -> String {
        guard argument.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "'" }) else {
            return argument
        }
        return "\"\(argument.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}

public struct CommandExecutionRequest: Sendable, Codable, Equatable {
    public let id: UUID
    public let workspaceBookmark: Data
    public let command: String
    public let arguments: [String]
    public let workingDirectory: String
    public let additionalReadBookmarks: [Data]
    public let timeoutSeconds: Double
    public let maxOutputBytes: Int

    public init(
        id: UUID,
        workspaceBookmark: Data,
        command: String,
        arguments: [String],
        workingDirectory: String,
        additionalReadBookmarks: [Data] = [],
        timeoutSeconds: Double,
        maxOutputBytes: Int
    ) {
        self.id = id
        self.workspaceBookmark = workspaceBookmark
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.additionalReadBookmarks = additionalReadBookmarks
        self.timeoutSeconds = timeoutSeconds
        self.maxOutputBytes = maxOutputBytes
    }
}

public struct CommandExecutionResponse: Sendable, Codable, Equatable {
    public let id: UUID
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let outputTruncated: Bool
    public let timedOut: Bool
    public let cancelled: Bool
    public let durationSeconds: Double
    public let errorMessage: String?

    public init(
        id: UUID,
        exitCode: Int32,
        stdout: String,
        stderr: String,
        outputTruncated: Bool,
        timedOut: Bool,
        cancelled: Bool,
        durationSeconds: Double,
        errorMessage: String?
    ) {
        self.id = id
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.outputTruncated = outputTruncated
        self.timedOut = timedOut
        self.cancelled = cancelled
        self.durationSeconds = durationSeconds
        self.errorMessage = errorMessage
    }

    public var isSuccess: Bool {
        exitCode == 0 && !timedOut && !cancelled && errorMessage == nil
    }
}

public enum WorkspaceProcessState: String, Sendable, Codable, Equatable {
    case running
    case exited
    case stopped
    case failed
}

public struct WorkspaceProcessSnapshot: Sendable, Codable, Equatable {
    public let id: UUID
    public let state: WorkspaceProcessState
    public let result: CommandExecutionResponse?
    public let errorMessage: String?

    public init(
        id: UUID,
        state: WorkspaceProcessState,
        result: CommandExecutionResponse?,
        errorMessage: String?
    ) {
        self.id = id
        self.state = state
        self.result = result
        self.errorMessage = errorMessage
    }
}

@objc(QwenPrimeCommandServiceProtocol)
public protocol QwenPrimeCommandServiceProtocol {
    func executeCommand(
        requestData: Data,
        withReply reply: @escaping @Sendable (Data) -> Void
    )

    func cancelCommand(
        id: UUID,
        withReply reply: @escaping @Sendable (Bool) -> Void
    )

    func startCommand(
        requestData: Data,
        withReply reply: @escaping @Sendable (Data) -> Void
    )

    func commandStatus(
        id: UUID,
        withReply reply: @escaping @Sendable (Data) -> Void
    )

    func stopCommand(
        id: UUID,
        withReply reply: @escaping @Sendable (Data) -> Void
    )
}

public enum QwenPrimeCommandServiceConstants {
    public static let serviceName = "app.dech.qwenprime.command-helper"
}
