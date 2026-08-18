import Foundation
import Testing
@testable import QwenPrime

@Suite("Workspace task staging")
struct WorkspaceTaskStagerTests {
    @Test("Stages bounded regular text package files while excluding generated and secret paths")
    func stagesTextPackage() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: "Package/Package.swift", content: "// package\n")
            try fixture.createFile(at: "Package/Sources/App.swift", content: "public let value = 1\n")
            try fixture.createFile(at: "Package/Tests/AppTests.swift", content: "// test\n")
            try fixture.createFile(at: "Package/.git/config", content: "secret\n")
            try fixture.createFile(at: "Package/.build/generated.swift", content: "generated\n")
            let cache = FileManager.default.temporaryDirectory
                .appendingPathComponent("qwen-task-stage-cache-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: cache) }

            let stage = try await WorkspaceTaskStager.stage(
                workspaceURL: fixture.rootURL,
                relativePackagePath: "Package",
                taskCacheURL: cache,
                id: UUID()
            )
            defer { try? stage.remove() }

            #expect(FileManager.default.fileExists(atPath: stage.workspaceURL.appendingPathComponent("Package.swift").path))
            #expect(FileManager.default.fileExists(atPath: stage.workspaceURL.appendingPathComponent("Sources/App.swift").path))
            #expect(FileManager.default.fileExists(atPath: stage.workspaceURL.appendingPathComponent("Tests/AppTests.swift").path))
            #expect(!FileManager.default.fileExists(atPath: stage.workspaceURL.appendingPathComponent(".git/config").path))
            #expect(!FileManager.default.fileExists(atPath: stage.workspaceURL.appendingPathComponent(".build/generated.swift").path))
            #expect(stage.relativeWorkingDirectory.hasSuffix("/workspace"))
        }
    }

    @Test("Rejects symbolic links instead of following them into the task cache")
    func rejectsSymbolicLinks() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: "Package/Package.swift", content: "// package\n")
            try fixture.createSymlink(at: "Package/Sources/link.swift", pointingTo: "/tmp/outside.swift")
            let cache = FileManager.default.temporaryDirectory
                .appendingPathComponent("qwen-task-stage-link-cache-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: cache) }

            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await WorkspaceTaskStager.stage(
                    workspaceURL: fixture.rootURL,
                    relativePackagePath: "Package",
                    taskCacheURL: cache,
                    id: UUID()
                )
            }
        }
    }

    @Test("Rejects task caches that overlap the original workspace")
    func rejectsOverlappingCache() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: "Package/Package.swift", content: "// package\n")

            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await WorkspaceTaskStager.stage(
                    workspaceURL: fixture.rootURL,
                    relativePackagePath: "Package",
                    taskCacheURL: fixture.rootURL,
                    id: UUID()
                )
            }
            let nestedCache = fixture.rootURL.appendingPathComponent("BuildCache", isDirectory: true)
            try FileManager.default.createDirectory(at: nestedCache, withIntermediateDirectories: true)
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await WorkspaceTaskStager.stage(
                    workspaceURL: fixture.rootURL,
                    relativePackagePath: "Package",
                    taskCacheURL: nestedCache,
                    id: UUID()
                )
            }
        }
    }
}
