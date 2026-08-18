import Foundation
import Testing
@testable import QwenPrimeCommandCore
import QwenPrimeCommandProtocol

@Suite("Sandboxed command policy and runner")
struct CommandPolicyAndRunnerTests {
    @Test("Policy accepts the bounded initial command surface")
    func acceptsBoundedCommands() throws {
        #expect(throws: Never.self) {
            try WorkspaceCommandPolicy.validate(command: "pwd", arguments: [])
        }
        #expect(throws: Never.self) {
            try WorkspaceCommandPolicy.validate(command: "ls", arguments: ["-la"])
        }
        for arguments in [
            ["log", "-n", "5"],
            ["log", "--oneline", "--max-count=10", "HEAD"],
            ["rev-parse", "--show-toplevel"],
            ["rev-parse", "--abbrev-ref", "HEAD"]
        ] {
            #expect(throws: Never.self) {
                try WorkspaceCommandPolicy.validate(command: "git", arguments: arguments)
            }
        }
    }

    @Test("Policy rejects shells, Git mutations, unsafe Swift flags, and path escapes")
    func rejectsUnsafeCommands() {
        #expect(throws: CommandPolicyError.self) {
            try WorkspaceCommandPolicy.validate(command: "sh", arguments: ["-c", "echo unsafe"])
        }
        #expect(throws: CommandPolicyError.self) {
            try WorkspaceCommandPolicy.validate(command: "git", arguments: ["push"])
        }
        #expect(throws: CommandPolicyError.self) {
            try WorkspaceCommandPolicy.validate(command: "git", arguments: ["status", "--short"])
        }
        #expect(throws: CommandPolicyError.self) {
            try WorkspaceCommandPolicy.validate(command: "git", arguments: ["diff", "--stat"])
        }
        #expect(throws: CommandPolicyError.self) {
            try WorkspaceCommandPolicy.validate(command: "git", arguments: ["show", "HEAD"])
        }
        #expect(throws: CommandPolicyError.self) {
            try WorkspaceCommandPolicy.validate(command: "swift", arguments: ["test", "--disable-sandbox"])
        }
        #expect(throws: CommandPolicyError.self) {
            try WorkspaceCommandPolicy.validate(command: "ls", arguments: ["Sources"])
        }
        #expect(throws: CommandPolicyError.self) {
            try WorkspaceCommandPolicy.validate(command: "ls", arguments: ["-"])
        }
    }

    @Test("Git launch arguments force metadata-only log behavior")
    func gitLaunchArgumentsAreHardened() throws {
        let executable = try WorkspaceCommandPolicy.executableURL(for: "git")
        #expect(executable.path != "/usr/bin/git")
        #expect(executable.lastPathComponent == "git")

        let arguments = try WorkspaceCommandPolicy.launchArguments(
            command: "git",
            arguments: ["log", "--oneline", "-n", "5"]
        )
        #expect(arguments.prefix(6) == [
            "-c", "core.fsmonitor=false",
            "-c", "core.hooksPath=/dev/null",
            "-c", "core.pager=cat"
        ])
        #expect(arguments.contains("--no-patch"))
        #expect(arguments.contains("--no-show-signature"))

        let environment = WorkspaceCommandPolicy.sanitizedEnvironment()
        #expect(environment["GIT_CONFIG_NOSYSTEM"] == "1")
        #expect(environment["GIT_CONFIG_GLOBAL"] == "/dev/null")
        #expect(environment["GIT_OPTIONAL_LOCKS"] == "0")
    }

    @Test("Command request and response round-trip without shell text")
    func contractsRoundTrip() throws {
        let request = CommandExecutionRequest(
            id: UUID(),
            workspaceBookmark: Data([1, 2, 3]),
            command: "git",
            arguments: ["rev-parse", "--show-toplevel"],
            workingDirectory: "Sources",
            additionalReadBookmarks: [Data([4, 5, 6])],
            timeoutSeconds: 30,
            maxOutputBytes: 65_536
        )
        let requestData = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(CommandExecutionRequest.self, from: requestData) == request)

        let response = CommandExecutionResponse(
            id: request.id,
            exitCode: 0,
            stdout: "clean\n",
            stderr: "",
            outputTruncated: false,
            timedOut: false,
            cancelled: false,
            durationSeconds: 0.1,
            errorMessage: nil
        )
        let responseData = try JSONEncoder().encode(response)
        #expect(try JSONDecoder().decode(CommandExecutionResponse.self, from: responseData) == response)
    }

    @Test("Runner captures stdout and nonzero exit status")
    func runnerCapturesResults() async throws {
        let success = try await BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/pwd"),
            arguments: [],
            workingDirectory: FileManager.default.temporaryDirectory,
            timeoutSeconds: 5,
            maxOutputBytes: 4096
        )
        #expect(success.exitCode == 0)
        #expect(!success.stdout.isEmpty)

        let failure = try await BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/ls"),
            arguments: ["definitely-not-present-\(UUID().uuidString)"],
            workingDirectory: FileManager.default.temporaryDirectory,
            timeoutSeconds: 5,
            maxOutputBytes: 4096
        )
        #expect(failure.exitCode != 0)
        #expect(!failure.stderr.isEmpty)
    }

    @Test("Runner enforces combined output cap and timeout")
    func runnerCapsOutputAndTimesOut() async throws {
        let capped = try await BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/seq"),
            arguments: ["1", "10000"],
            workingDirectory: FileManager.default.temporaryDirectory,
            timeoutSeconds: 5,
            maxOutputBytes: 128
        )
        #expect(capped.stdout.utf8.count <= 128)
        #expect(capped.outputTruncated)

        let timedOut = try await BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["2"],
            workingDirectory: FileManager.default.temporaryDirectory,
            timeoutSeconds: 0.05,
            maxOutputBytes: 128
        )
        #expect(timedOut.timedOut)
    }
}
