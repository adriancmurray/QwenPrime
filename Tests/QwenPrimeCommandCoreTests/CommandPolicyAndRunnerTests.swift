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
        #expect(throws: Never.self) {
            try WorkspaceCommandPolicy.validate(command: "swift", arguments: ["build"])
        }
        #expect(throws: Never.self) {
            try WorkspaceCommandPolicy.validate(
                command: "swift",
                arguments: ["test", "--filter", "ReadOnlyWorkspaceServiceTests"]
            )
        }
    }

    @Test("Swift task launch arguments inject an isolated scratch path and cannot be supplied by the model")
    func swiftTaskLaunchArgumentsAreIsolated() throws {
        let scratchPath = URL(fileURLWithPath: "/Users/example/QwenPrimeBuildCache", isDirectory: true)
            .appendingPathComponent("QwenPrimeCommandTasks", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("scratch", isDirectory: true)
            .path
        let arguments = try WorkspaceCommandPolicy.launchArguments(
            command: "swift",
            arguments: ["test", "--filter", "ReadOnlyWorkspaceServiceTests"],
            scratchPath: scratchPath
        )

        #expect(arguments == [
            "test",
            "--disable-sandbox",
            "--scratch-path", scratchPath,
            "--filter", "ReadOnlyWorkspaceServiceTests"
        ])
        #expect(throws: CommandPolicyError.self) {
            try WorkspaceCommandPolicy.validate(
                command: "swift",
                arguments: ["test", "--scratch-path", "/tmp/attacker"]
            )
        }
        #expect(throws: CommandPolicyError.self) {
            try WorkspaceCommandPolicy.launchArguments(
                command: "swift",
                arguments: ["build"],
                scratchPath: nil
            )
        }
    }

    @Test("Swift task environment resolves a coherent toolchain without xcrun")
    func swiftTaskEnvironmentAvoidsXcrun() throws {
        let executable = try WorkspaceCommandPolicy.executableURL(for: "swift")
        let environment = try WorkspaceCommandPolicy.swiftTaskEnvironment(
            executableURL: executable,
            base: WorkspaceCommandPolicy.sanitizedEnvironment()
        )

        let sdkRoot = try #require(environment["SDKROOT"])
        let binDirectory = try #require(environment["SWIFTPM_CUSTOM_BIN_DIR"])
        let platformPath = try #require(environment["SWIFTPM_PLATFORM_PATH_macosx"])
        #expect(FileManager.default.fileExists(atPath: sdkRoot))
        #expect(FileManager.default.fileExists(atPath: binDirectory + "/swiftc"))
        #expect(FileManager.default.fileExists(atPath: binDirectory + "/clang"))
        #expect(FileManager.default.fileExists(atPath: platformPath + "/Developer/Library/Frameworks"))
        #expect(environment["SWIFT_EXEC"] == binDirectory + "/swiftc")
        #expect(environment["SWIFT_EXEC_MANIFEST"] == binDirectory + "/swiftc")
        #expect(environment["CC"] == binDirectory + "/clang")
        #expect(environment["LIBTOOL"] == binDirectory + "/libtool")
    }

    @Test("Swift task context owns isolated scratch and home directories and removes them")
    func swiftTaskContextLifecycle() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appendingPathComponent("qwen-prime-task-context-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let context = try SwiftTaskExecutionContext.create(
            id: UUID(),
            temporaryRoot: temporaryRoot
        )
        #expect(FileManager.default.fileExists(atPath: context.scratchURL.path))
        #expect(FileManager.default.fileExists(atPath: context.homeURL.path))
        #expect(FileManager.default.fileExists(atPath: context.moduleCacheURL.path))
        #expect(FileManager.default.fileExists(atPath: context.profileDataURL.path))
        let environment = context.environment(
            base: WorkspaceCommandPolicy.sanitizedEnvironment()
        )
        #expect(environment["HOME"] == context.homeURL.path)
        #expect(environment["CFFIXED_USER_HOME"] == context.homeURL.path)
        #expect(environment["SWIFTPM_MODULECACHE_OVERRIDE"] == context.moduleCacheURL.path)
        #expect(environment["SWIFTPM_TESTS_MODULECACHE"] == context.moduleCacheURL.path)
        #expect(environment["CLANG_MODULE_CACHE_PATH"] == context.moduleCacheURL.path)
        #expect(environment["XDG_CACHE_HOME"] == context.rootURL.appendingPathComponent("cache").path)
        #expect(environment["LLVM_PROFILE_FILE"] == context.profileDataURL.appendingPathComponent("%p.profraw").path)

        try context.remove()
        #expect(!FileManager.default.fileExists(atPath: context.rootURL.path))
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
}
