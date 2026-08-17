import Foundation
import Testing
@testable import QwenPrime

struct TestWorkspaceBookmarker: WorkspaceBookmarking {
    func createBookmark(for url: URL) throws -> Data {
        Data(url.standardizedFileURL.path.utf8)
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedWorkspaceBookmark {
        guard let path = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return ResolvedWorkspaceBookmark(
            url: URL(fileURLWithPath: path, isDirectory: true),
            isStale: false
        )
    }
}

final class TestWorkspaceSecurityScopeAccessor: WorkspaceSecurityScopeAccessing, @unchecked Sendable {
    private let lock = NSLock()
    let grantsAccess: Bool
    private var starts = 0
    private var stops = 0

    init(grantsAccess: Bool = true) {
        self.grantsAccess = grantsAccess
    }

    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }

    func startAccessing(_ url: URL) -> Bool {
        lock.withLock { starts += 1 }
        return grantsAccess
    }

    func stopAccessing(_ url: URL) {
        lock.withLock { stops += 1 }
    }
}

@Suite("Workspace security-scoped authorization")
@MainActor
struct WorkspaceAuthorizationServiceTests {
    @Test("Selected workspace bookmark persists and resolves after service recreation")
    func testBookmarkPersistsAndResolves() throws {
        let suiteName = "WorkspaceAuthorizationServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("authorized-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let first = WorkspaceAuthorizationService(
            userDefaults: defaults,
            bookmarker: TestWorkspaceBookmarker(),
            scopeAccessor: TestWorkspaceSecurityScopeAccessor()
        )
        let authorized = try first.authorize(workspace)
        #expect(authorized.standardizedFileURL == workspace.standardizedFileURL)
        #expect(first.isAuthorized(path: workspace.path))

        let restored = WorkspaceAuthorizationService(
            userDefaults: defaults,
            bookmarker: TestWorkspaceBookmarker(),
            scopeAccessor: TestWorkspaceSecurityScopeAccessor()
        )
        let resolved = try #require(restored.resolveAuthorizedURL(path: workspace.path))
        #expect(resolved.standardizedFileURL == workspace.standardizedFileURL)
        #expect(restored.authorizedURLs.map(\.path).contains(workspace.path))
    }

    @Test("Unselected path has no durable authorization")
    func testUnselectedPathIsNotAuthorized() throws {
        let suiteName = "WorkspaceAuthorizationServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = WorkspaceAuthorizationService(
            userDefaults: defaults,
            bookmarker: TestWorkspaceBookmarker(),
            scopeAccessor: TestWorkspaceSecurityScopeAccessor()
        )

        #expect(!service.isAuthorized(path: "/private/tmp/not-selected"))
        #expect(service.resolveAuthorizedURL(path: "/private/tmp/not-selected") == nil)
    }

    @Test("Repeated authorization reuses one balanced security-scope activation")
    func testRepeatedAuthorizationBalancesScope() throws {
        let suiteName = "WorkspaceAuthorizationServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let accessor = TestWorkspaceSecurityScopeAccessor()
        let workspace = URL(fileURLWithPath: "/private/tmp/repeated-workspace", isDirectory: true)

        var service: WorkspaceAuthorizationService? = WorkspaceAuthorizationService(
            userDefaults: defaults,
            bookmarker: TestWorkspaceBookmarker(),
            scopeAccessor: accessor
        )
        _ = try service?.authorize(workspace)
        _ = try service?.authorize(workspace)
        #expect(accessor.startCount == 1)

        service = nil
        #expect(accessor.stopCount == 1)
    }

    @Test("Failed security-scope activation is not treated as authorization")
    func testFailedScopeActivationIsRejected() throws {
        let suiteName = "WorkspaceAuthorizationServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let workspace = URL(fileURLWithPath: "/private/tmp/denied-workspace", isDirectory: true)
        let service = WorkspaceAuthorizationService(
            userDefaults: defaults,
            bookmarker: TestWorkspaceBookmarker(),
            scopeAccessor: TestWorkspaceSecurityScopeAccessor(grantsAccess: false)
        )

        #expect(throws: WorkspaceAccessError.self) {
            _ = try service.authorize(workspace)
        }
        #expect(!service.isAuthorized(path: workspace.path))
    }
}
