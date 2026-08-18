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
            try WorkspaceCommandPolicy.validate(command: "swift", arguments: ["test", "--disable-sandbox"])
        }
        #expect(throws: CommandPolicyError.self) {
            try WorkspaceCommandPolicy.validate(command: "ls", arguments: ["Sources"])
        }
        #expect(throws: CommandPolicyError.self) {
            try WorkspaceCommandPolicy.validate(command: "ls", arguments: ["-"])
        }
    }

    @Test("Command request and response round-trip without shell text")
    func contractsRoundTrip() throws {
        let request = CommandExecutionRequest(
            id: UUID(),
            workspaceBookmark: Data([1, 2, 3]),
            command: "git",
            arguments: ["status", "--short"],
            workingDirectory: "Sources",
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
