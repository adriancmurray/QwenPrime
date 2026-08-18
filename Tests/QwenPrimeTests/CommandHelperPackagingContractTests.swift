import Foundation
import Testing
@testable import QwenPrime

@Suite("Command helper packaging contract")
struct CommandHelperPackagingContractTests {
    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    @Test("Transient interprocess bookmarks are resolved directly instead of rejected as stale")
    func transientBookmarkResolution() throws {
        let helper = try source("Sources/QwenPrimeCommandHelper/CommandService.swift")
        #expect(helper.contains("resolvingBookmarkData: request.workspaceBookmark"))
        #expect(helper.contains("relativeTo: nil"))
        #expect(!helper.contains("guard !isStale"))
    }

    @Test("Packaged helper is App Sandbox enabled without network entitlement")
    func helperEntitlements() throws {
        let entitlements = try source("Entitlements/QwenPrimeCommandHelper.entitlements")
        #expect(entitlements.contains("com.apple.security.app-sandbox"))
        #expect(entitlements.contains("com.apple.security.files.user-selected.read-only"))
        #expect(!entitlements.contains("com.apple.security.files.user-selected.read-write"))
        #expect(!entitlements.contains("com.apple.security.network.client"))
        #expect(!entitlements.contains("com.apple.security.network.server"))
    }
}
