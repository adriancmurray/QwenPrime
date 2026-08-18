import Foundation
import Testing
@testable import QwenPrimeCommandCore
import QwenPrimeCommandProtocol

@Suite("Git worktree metadata resource grants")
struct GitWorktreeMetadataResolverTests {
    @Test("Self-contained repository needs no secondary grant")
    func selfContainedRepository() throws {
        let root = try temporaryDirectory(named: "SelfContained")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )

        #expect(try GitWorktreeMetadataResolver.requiredReadGrants(workspaceURL: root).isEmpty)
    }

    @Test("Linked worktree discloses worktree and common Git metadata directories")
    func linkedWorktreeGrants() throws {
        let fixture = try makeLinkedWorktreeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }

        let grants = try GitWorktreeMetadataResolver.requiredReadGrants(
            workspaceURL: fixture.workspace
        )

        #expect(grants == [
            CommandResourceGrant(path: fixture.worktreeGitDirectory.path, access: .readOnly),
            CommandResourceGrant(path: fixture.commonGitDirectory.path, access: .readOnly)
        ])
    }

    @Test("Worktree metadata pointer must contain a verified backlink")
    func rejectsMismatchedBacklink() throws {
        let fixture = try makeLinkedWorktreeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        try "/different/workspace/.git\n".write(
            to: fixture.worktreeGitDirectory.appendingPathComponent("gitdir"),
            atomically: true,
            encoding: .utf8
        )

        #expect(throws: GitWorktreeMetadataError.self) {
            try GitWorktreeMetadataResolver.requiredReadGrants(
                workspaceURL: fixture.workspace
            )
        }
    }

    @Test("Command preview explicitly lists secondary read-only grants")
    func commandPreviewDisclosesGrants() {
        let proposal = WorkspaceCommandProposal(
            command: "git",
            arguments: ["rev-parse", "HEAD"],
            resourceGrants: [
                CommandResourceGrant(path: "/repo/.git", access: .readOnly)
            ]
        )

        #expect(proposal.preview.contains("Additional read-only access"))
        #expect(proposal.preview.contains("/repo/.git"))
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeLinkedWorktreeFixture() throws -> (
        base: URL,
        workspace: URL,
        worktreeGitDirectory: URL,
        commonGitDirectory: URL
    ) {
        let base = try temporaryDirectory(named: "LinkedWorktree")
        let workspace = base.appendingPathComponent("workspace", isDirectory: true)
        let common = base.appendingPathComponent("repository/.git", isDirectory: true)
        let worktreeGit = common.appendingPathComponent("worktrees/workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeGit, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: common.appendingPathComponent("objects", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: common.appendingPathComponent("refs", isDirectory: true),
            withIntermediateDirectories: true
        )

        let dotGit = workspace.appendingPathComponent(".git")
        try "gitdir: \(worktreeGit.path)\n".write(to: dotGit, atomically: true, encoding: .utf8)
        try "ref: refs/heads/test\n".write(
            to: worktreeGit.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8
        )
        try "../..\n".write(
            to: worktreeGit.appendingPathComponent("commondir"), atomically: true, encoding: .utf8
        )
        try "\(dotGit.path)\n".write(
            to: worktreeGit.appendingPathComponent("gitdir"), atomically: true, encoding: .utf8
        )
        return (base, workspace, worktreeGit, common)
    }
}
