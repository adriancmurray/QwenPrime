import Foundation

public struct WorkspaceCommandProposal: Sendable, Codable, Equatable, Hashable {
    public let command: String
    public let arguments: [String]
    public let workingDirectory: String

    public init(
        command: String,
        arguments: [String],
        workingDirectory: String = ""
    ) {
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }

    public var preview: String {
        let renderedArguments = arguments.map(Self.quoteForDisplay).joined(separator: " ")
        let commandLine = renderedArguments.isEmpty ? command : "\(command) \(renderedArguments)"
        let directory = workingDirectory.isEmpty ? "." : workingDirectory
        return "$ \(commandLine)\nworking directory: \(directory)"
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
    public let timeoutSeconds: Double
    public let maxOutputBytes: Int

    public init(
        id: UUID,
        workspaceBookmark: Data,
        command: String,
        arguments: [String],
        workingDirectory: String,
        timeoutSeconds: Double,
        maxOutputBytes: Int
    ) {
        self.id = id
        self.workspaceBookmark = workspaceBookmark
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
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
}

public enum QwenPrimeCommandServiceConstants {
    public static let serviceName = "app.dech.qwenprime.command-helper"
}
