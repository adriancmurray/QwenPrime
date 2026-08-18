import Foundation
import QwenPrimeCommandCore
import QwenPrimeCommandProtocol

public struct SeatbeltWorkspaceTaskExecutor: WorkspaceCommandExecuting, Sendable {
    private let workspaceURL: URL
    private let taskCacheURL: URL

    public init(workspaceURL: URL, taskCacheURL: URL) {
        self.workspaceURL = workspaceURL.standardizedFileURL
        self.taskCacheURL = taskCacheURL.standardizedFileURL
    }

    public func prepare(
        _ proposal: WorkspaceCommandProposal
    ) async throws -> WorkspaceCommandProposal {
        guard proposal.command == "swift" else {
            throw CommandPolicyError.unsupportedCommand(proposal.command)
        }
        try WorkspaceCommandPolicy.validate(
            command: proposal.command,
            arguments: proposal.arguments
        )
        _ = try ReadOnlyWorkspaceService.validateAndParseDirectoryPath(
            proposal.workingDirectory
        )
        return proposal
    }

    public func execute(
        _ proposal: WorkspaceCommandProposal
    ) async throws -> CommandExecutionResponse {
        _ = try await prepare(proposal)
        let id = UUID()
        let stage = try await WorkspaceTaskStager.stage(
            workspaceURL: workspaceURL,
            relativePackagePath: proposal.workingDirectory,
            taskCacheURL: taskCacheURL,
            id: id
        )
        defer { try? stage.remove() }

        let context = try SwiftTaskExecutionContext.create(
            id: id,
            temporaryRoot: taskCacheURL.appendingPathComponent(
                "QwenPrimeCommandTasks",
                isDirectory: true
            )
        )
        defer { try? context.remove() }

        let swiftURL = try WorkspaceCommandPolicy.executableURL(for: "swift")
        let environment = context.environment(
            base: try WorkspaceCommandPolicy.swiftTaskEnvironment(
                executableURL: swiftURL,
                base: WorkspaceCommandPolicy.sanitizedEnvironment()
            )
        )
        let swiftArguments = try WorkspaceCommandPolicy.launchArguments(
            command: proposal.command,
            arguments: proposal.arguments,
            scratchPath: context.scratchURL.path
        )
        let response = try await BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
            arguments: [
                "-p", Self.profile(taskCacheURL: taskCacheURL),
                swiftURL.path
            ] + swiftArguments,
            workingDirectory: stage.workspaceURL,
            timeoutSeconds: 60,
            maxOutputBytes: 64 * 1024,
            environment: environment
        )
        return sanitized(response)
    }

    static func profile(taskCacheURL: URL) -> String {
        let cachePath = escape(taskCacheURL.standardizedFileURL.resolvingSymlinksInPath().path)
        return """
        (version 1)
        (deny default)

        (allow process-exec)
        (allow process-fork)
        (allow process-info* (target same-sandbox))
        (allow signal (target same-sandbox))
        (allow mach-priv-task-port (target same-sandbox))

        (allow user-preference-read)
        (allow ipc-posix-shm)
        (allow ipc-posix-sem)
        (allow sysctl-read)
        (allow iokit-get-properties)
        (allow system-socket (require-all (socket-domain AF_SYSTEM) (socket-protocol 2)))

        (allow mach-lookup
          (global-name "com.apple.bsd.dirhelper")
          (global-name "com.apple.FontObjectsServer")
          (global-name "com.apple.fonts")
          (global-name "com.apple.logd")
          (global-name "com.apple.SecurityServer")
          (global-name "com.apple.securityd.xpc")
          (global-name "com.apple.system.logger")
          (global-name "com.apple.system.opendirectoryd.libinfo")
          (global-name "com.apple.system.opendirectoryd.membership"))

        (allow file-read-metadata (vnode-type DIRECTORY))
        (allow file-read* (literal "/"))
        (allow file-read* (subpath "/System"))
        (allow file-read* (subpath "/usr"))
        (allow file-read* (subpath "/bin"))
        (allow file-read* (subpath "/sbin"))
        (allow file-read* (subpath "/Library/Developer"))
        (allow file-read* (subpath "/Library/Frameworks"))
        (allow file-read* (subpath "/Library/Apple"))
        (allow file-read* (subpath "/Applications/Xcode.app"))
        (allow file-read* (subpath "/Applications/Xcode-beta.app"))
        (allow file-read* (subpath "/private/etc"))
        (allow file-read* (subpath "/private/var/db/dyld"))
        (allow file-read* (subpath "/private/var/db/timezone"))
        (allow file-read* (subpath "/private/var/select"))
        (allow file-read* (subpath "/dev"))
        (allow file-read* (subpath "\(cachePath)"))
        (allow file-write* (subpath "\(cachePath)"))

        (allow file-ioctl
          (literal "/dev/null")
          (literal "/dev/zero")
          (literal "/dev/random")
          (literal "/dev/urandom"))
        (allow file-read-data file-write-data
          (literal "/dev/null")
          (literal "/dev/zero")
          (literal "/dev/random")
          (literal "/dev/urandom"))
        """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func sanitized(_ response: CommandExecutionResponse) -> CommandExecutionResponse {
        let cachePaths = [
            taskCacheURL.path,
            taskCacheURL.standardizedFileURL.path,
            taskCacheURL.resolvingSymlinksInPath().path
        ].sorted { $0.count > $1.count }
        func sanitize(_ value: String) -> String {
            cachePaths.reduce(value) { result, path in
                result.replacingOccurrences(of: path, with: "<task_cache>")
            }
        }
        return CommandExecutionResponse(
            id: response.id,
            exitCode: response.exitCode,
            stdout: sanitize(response.stdout),
            stderr: sanitize(response.stderr),
            outputTruncated: response.outputTruncated,
            timedOut: response.timedOut,
            cancelled: response.cancelled,
            durationSeconds: response.durationSeconds,
            errorMessage: response.errorMessage.map(sanitize)
        )
    }
}
