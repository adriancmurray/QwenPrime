import Foundation
import Testing
@testable import QwenPrime

@Suite("Task cache security-scoped authorization")
struct TaskCacheAuthorizationServiceTests {
    @Test("Selected task cache persists and resolves after service recreation")
    @MainActor
    func selectedCachePersists() throws {
        let suiteName = "QwenPrimeTests-TaskCache-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("task-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let first = TaskCacheAuthorizationService(
            userDefaults: defaults,
            bookmarker: TestWorkspaceBookmarker(),
            scopeAccessor: TestWorkspaceSecurityScopeAccessor()
        )
        #expect(try first.authorize(cacheURL).path == cacheURL.path)
        #expect(first.authorizedURL?.path == cacheURL.path)

        let restored = TaskCacheAuthorizationService(
            userDefaults: defaults,
            bookmarker: TestWorkspaceBookmarker(),
            scopeAccessor: TestWorkspaceSecurityScopeAccessor()
        )
        #expect(restored.authorizedURL?.path == cacheURL.path)
    }

    @Test("Replacing the task cache stops the previous security scope")
    @MainActor
    func replacingCacheBalancesScope() throws {
        let suiteName = "QwenPrimeTests-TaskCacheReplace-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scope = TestWorkspaceSecurityScopeAccessor()
        let firstURL = URL(fileURLWithPath: "/tmp/task-cache-a", isDirectory: true)
        let secondURL = URL(fileURLWithPath: "/tmp/task-cache-b", isDirectory: true)
        let service = TaskCacheAuthorizationService(
            userDefaults: defaults,
            bookmarker: TestWorkspaceBookmarker(),
            scopeAccessor: scope
        )

        _ = try service.authorize(firstURL)
        _ = try service.authorize(secondURL)

        #expect(scope.startCount == 2)
        #expect(scope.stopCount == 1)
        #expect(service.authorizedURL?.path == secondURL.path)
    }

    @Test("Rejects root, home, and control-character cache paths")
    @MainActor
    func rejectsUnsafeCacheRoots() throws {
        let suiteName = "QwenPrimeTests-TaskCacheUnsafe-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = TaskCacheAuthorizationService(
            userDefaults: defaults,
            bookmarker: TestWorkspaceBookmarker(),
            scopeAccessor: TestWorkspaceSecurityScopeAccessor()
        )

        #expect(throws: WorkspaceAccessError.self) {
            _ = try service.authorize(URL(fileURLWithPath: "/", isDirectory: true))
        }
        #expect(throws: WorkspaceAccessError.self) {
            _ = try service.authorize(FileManager.default.homeDirectoryForCurrentUser)
        }
        #expect(throws: WorkspaceAccessError.self) {
            _ = try service.authorize(URL(fileURLWithPath: "/tmp/cache\nrule", isDirectory: true))
        }
    }
}
