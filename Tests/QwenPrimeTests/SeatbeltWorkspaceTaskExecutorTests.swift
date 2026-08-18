import Foundation
import Testing
import QwenPrimeCommandProtocol
@testable import QwenPrime

@Suite("Seatbelt workspace task execution")
struct SeatbeltWorkspaceTaskExecutorTests {
    @Test("Seatbelt profile denies network and user files while allowing only task cache writes")
    func profileBoundary() {
        let cache = URL(fileURLWithPath: "/Users/example/QwenPrimeBuildCache", isDirectory: true)
        let profile = SeatbeltWorkspaceTaskExecutor.profile(taskCacheURL: cache)

        #expect(profile.contains("(deny default)"))
        #expect(!profile.contains("(allow network"))
        #expect(!profile.contains("(allow file-read*)"))
        #expect(profile.contains("(allow file-read* (subpath \"/System\"))"))
        #expect(profile.contains("(allow file-read* (subpath \"/Users/example/QwenPrimeBuildCache\"))"))
        #expect(profile.contains("(allow file-write* (subpath \"/Users/example/QwenPrimeBuildCache\"))"))
    }

    @Test("Runs a self-contained Swift test from a staged copy without modifying the workspace")
    func runsSwiftTestFromStage() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(
                at: "Fixture/Package.swift",
                content: """
                // swift-tools-version: 6.0
                import PackageDescription
                let package = Package(name: "Fixture", targets: [
                    .target(name: "Fixture"),
                    .testTarget(name: "FixtureTests", dependencies: ["Fixture"])
                ])
                """
            )
            try fixture.createFile(
                at: "Fixture/Sources/Fixture/Fixture.swift",
                content: "public func value() -> Int { 42 }\n"
            )
            try fixture.createFile(
                at: "Fixture/Tests/FixtureTests/FixtureTests.swift",
                content: """
                import Testing
                @testable import Fixture
                @Test func returnsValue() { #expect(value() == 42) }
                """
            )
            let cache = FileManager.default.temporaryDirectory
                .appendingPathComponent("qwen-seatbelt-task-cache-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: cache) }

            let executor = SeatbeltWorkspaceTaskExecutor(
                workspaceURL: fixture.rootURL,
                taskCacheURL: cache
            )
            let proposal = WorkspaceCommandProposal(
                command: "swift",
                arguments: ["test"],
                workingDirectory: "Fixture"
            )
            _ = try await executor.prepare(proposal)
            let response = try await executor.execute(proposal)

            if response.exitCode == 71,
               response.stderr.contains("sandbox_apply: Operation not permitted") {
                withKnownIssue("Nested agent sandboxes cannot create another Seatbelt profile") {
                    #expect(response.isSuccess)
                }
                return
            }

            #expect(response.isSuccess)
            #expect(response.stdout.contains("returnsValue") || response.stdout.contains("passed"))
            #expect(!FileManager.default.fileExists(atPath: fixture.rootURL.appendingPathComponent("Fixture/.build").path))
        }
    }
}
