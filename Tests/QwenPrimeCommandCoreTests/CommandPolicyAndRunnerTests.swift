import Foundation
import Testing
@testable import QwenPrimeCommandCore
import QwenPrimeCommandProtocol

@Suite("Sandboxed command policy and runner")
struct CommandPolicyAndRunnerTests {
    @Test("Policy accepts generic argv-only executables without a command allowlist")
    func acceptsGenericExecutables() throws {
        #expect(throws: Never.self) {
            try WorkspaceCommandPolicy.validate(
                command: "printf",
                arguments: ["hello %s\\n", "Qwen Prime"]
            )
        }
        #expect(throws: Never.self) {
            try WorkspaceCommandPolicy.validate(
                command: "swift",
                arguments: ["build", "--product", "HelloQwen"]
            )
        }
        #expect(throws: Never.self) {
            try WorkspaceCommandPolicy.validate(
                command: "./.build/debug/HelloQwen",
                arguments: []
            )
        }
    }

    @Test("Executable resolution searches trusted system locations without a name allowlist")
    func resolvesGenericSystemExecutable() throws {
        let executable = try WorkspaceCommandPolicy.executableURL(for: "printf")
        #expect(executable.path == "/usr/bin/printf")
    }

    @Test("Executable resolution permits a workspace-owned built artifact")
    func resolvesWorkspaceExecutable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwen-process-policy-\(UUID().uuidString)", isDirectory: true)
        let productDirectory = root.appendingPathComponent(".build/debug", isDirectory: true)
        let executable = productDirectory.appendingPathComponent("HelloQwen")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: productDirectory, withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let resolved = try WorkspaceCommandPolicy.executableURL(
            for: "./.build/debug/HelloQwen",
            workingDirectory: root,
            workspaceRoot: root
        )
        #expect(resolved == executable.resolvingSymlinksInPath())
    }

    @Test("Policy rejects absolute and escaping executable paths")
    func rejectsEscapingExecutablePaths() {
        #expect(throws: CommandPolicyError.self) {
            try WorkspaceCommandPolicy.validate(command: "/bin/echo", arguments: [])
        }
        #expect(throws: CommandPolicyError.self) {
            try WorkspaceCommandPolicy.validate(command: "../outside", arguments: [])
        }
        #expect(throws: CommandPolicyError.self) {
            try WorkspaceCommandPolicy.validate(command: "tools/../outside", arguments: [])
        }
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

        let snapshot = WorkspaceProcessSnapshot(
            id: request.id,
            state: .running,
            result: nil,
            errorMessage: nil
        )
        let snapshotData = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(WorkspaceProcessSnapshot.self, from: snapshotData) == snapshot)
    }

    @Test("Supervised process registry starts, reports, and stops generic work")
    func supervisedProcessLifecycle() async throws {
        let registry = SupervisedProcessRegistry(maximumEntries: 4)
        let id = UUID()
        let started = await registry.start(id: id) {
            do {
                try await Task.sleep(for: .seconds(30))
                return CommandExecutionResponse(
                    id: id,
                    exitCode: 0,
                    stdout: "done\n",
                    stderr: "",
                    outputTruncated: false,
                    timedOut: false,
                    cancelled: false,
                    durationSeconds: 30,
                    errorMessage: nil
                )
            } catch {
                return CommandExecutionResponse(
                    id: id,
                    exitCode: -1,
                    stdout: "",
                    stderr: "",
                    outputTruncated: false,
                    timedOut: false,
                    cancelled: true,
                    durationSeconds: 0,
                    errorMessage: "Command cancelled."
                )
            }
        }
        #expect(started.state == .running)
        #expect(await registry.status(id: id)?.state == .running)

        let stopped = try #require(await registry.stop(id: id))
        #expect(stopped.state == .stopped)
        #expect(await registry.status(id: id)?.state == .stopped)
    }

    @Test("Supervised process registry never exceeds its bounded live-process capacity")
    func supervisedProcessCapacity() async {
        let registry = SupervisedProcessRegistry(maximumEntries: 1)
        let firstID = UUID()
        let secondID = UUID()
        let first = await registry.start(id: firstID) {
            try? await Task.sleep(for: .seconds(30))
            return Self.cancelledResponse(id: firstID)
        }
        let second = await registry.start(id: secondID) {
            Self.cancelledResponse(id: secondID)
        }

        #expect(first.state == .running)
        #expect(second.state == .failed)
        #expect(second.errorMessage?.contains("limit") == true)
        #expect(await registry.status(id: firstID)?.state == .running)
        #expect(await registry.status(id: secondID) == nil)
        _ = await registry.stop(id: firstID)
    }

    @Test("Supervised process registry reports nonzero completion as failed")
    func supervisedProcessFailureState() async throws {
        let registry = SupervisedProcessRegistry()
        let id = UUID()
        _ = await registry.start(id: id) {
            CommandExecutionResponse(
                id: id, exitCode: 2, stdout: "", stderr: "failed\n",
                outputTruncated: false, timedOut: false, cancelled: false,
                durationSeconds: 0, errorMessage: nil
            )
        }
        var snapshot: WorkspaceProcessSnapshot?
        for _ in 0..<100 {
            snapshot = await registry.status(id: id)
            if snapshot?.state != .running { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(snapshot?.state == .failed)
        #expect(snapshot?.result?.exitCode == 2)
    }

    @Test("Generic process substrate builds and launches a fresh AppKit executable")
    func buildsAndLaunchesHelloApp() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwen-hello-app-\(UUID().uuidString)", isDirectory: true)
        let sources = root.appendingPathComponent("Sources/HelloQwen", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(
            name: "HelloQwen",
            platforms: [.macOS(.v14)],
            targets: [.executableTarget(name: "HelloQwen")]
        )
        """.write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        try """
        import AppKit
        if CommandLine.arguments.contains("--self-test") {
            print("Hello from Qwen Prime")
        } else {
            _ = NSApplication.shared
        }
        """.write(
            to: sources.appendingPathComponent("main.swift"),
            atomically: true,
            encoding: .utf8
        )

        let swift = try WorkspaceCommandPolicy.executableURL(for: "swift")
        let build = try await BoundedProcessRunner.run(
            executableURL: swift,
            arguments: ["build", "--product", "HelloQwen"],
            workingDirectory: root,
            timeoutSeconds: 60,
            maxOutputBytes: 64 * 1024
        )
        #expect(build.isSuccess, Comment(rawValue: build.stderr))

        let executable = try WorkspaceCommandPolicy.executableURL(
            for: "./.build/debug/HelloQwen",
            workingDirectory: root,
            workspaceRoot: root
        )
        let launched = try await BoundedProcessRunner.run(
            executableURL: executable,
            arguments: ["--self-test"],
            workingDirectory: root,
            timeoutSeconds: 5,
            maxOutputBytes: 4096
        )
        #expect(launched.isSuccess)
        #expect(launched.stdout == "Hello from Qwen Prime\n")
    }

    @Test("Runner captures stdout and nonzero exit status")
    func runnerCapturesResults() async throws {
        let input = Data("typed-jsonl\n".utf8)
        let echoed = try await BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/cat"),
            arguments: [],
            workingDirectory: FileManager.default.temporaryDirectory,
            timeoutSeconds: 5,
            maxOutputBytes: 4096,
            standardInput: input
        )
        #expect(echoed.stdout == "typed-jsonl\n")

        await #expect(throws: CommandPolicyError.limitsExceeded) {
            _ = try await BoundedProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/true"),
                arguments: [],
                workingDirectory: FileManager.default.temporaryDirectory,
                timeoutSeconds: BoundedProcessRunner.maximumTimeoutSeconds + 1,
                maxOutputBytes: 4096
            )
        }

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

        let blockedInput = try await BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["2"],
            workingDirectory: FileManager.default.temporaryDirectory,
            timeoutSeconds: 0.05,
            maxOutputBytes: 128,
            standardInput: Data(repeating: 0x41, count: 1_048_576)
        )
        #expect(blockedInput.timedOut)
        #expect(blockedInput.durationSeconds < 1.5)

        let childHoldingPipes = try await BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 3 & wait"],
            workingDirectory: FileManager.default.temporaryDirectory,
            timeoutSeconds: 0.05,
            maxOutputBytes: 128
        )
        #expect(childHoldingPipes.timedOut)
        #expect(childHoldingPipes.durationSeconds < 1.5)
    }

    private static func cancelledResponse(id: UUID) -> CommandExecutionResponse {
        CommandExecutionResponse(
            id: id, exitCode: -1, stdout: "", stderr: "",
            outputTruncated: false, timedOut: false, cancelled: true,
            durationSeconds: 0, errorMessage: "Command cancelled."
        )
    }
}
