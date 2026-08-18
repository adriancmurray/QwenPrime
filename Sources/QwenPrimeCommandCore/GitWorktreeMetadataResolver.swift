import Foundation
import Darwin
import QwenPrimeCommandProtocol

public enum GitWorktreeMetadataError: Error, Sendable, Equatable, LocalizedError {
    case invalidPointer
    case invalidStructure
    case metadataTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidPointer:
            return "The linked Git worktree pointer is invalid."
        case .invalidStructure:
            return "The linked Git worktree metadata structure is invalid."
        case .metadataTooLarge:
            return "The linked Git worktree metadata pointer is too large."
        }
    }
}

public enum GitWorktreeMetadataResolver {
    public static func requiredReadGrants(
        workspaceURL: URL
    ) throws -> [CommandResourceGrant] {
        let workspace = workspaceURL.standardizedFileURL.resolvingSymlinksInPath()
        let dotGit = workspace.appendingPathComponent(".git")
        var dotGitInfo = stat()
        if lstat(dotGit.path, &dotGitInfo) != 0 {
            return []
        }
        let dotGitType = dotGitInfo.st_mode & S_IFMT
        if dotGitType == S_IFDIR {
            return []
        }
        guard dotGitType == S_IFREG else {
            throw GitWorktreeMetadataError.invalidPointer
        }

        let worktreeGitDirectory = try resolveGitDirectoryPointer(
            fileURL: dotGit,
            prefix: "gitdir: ",
            relativeTo: workspace
        )
        try requireDirectory(worktreeGitDirectory)
        try requireRegularFile(worktreeGitDirectory.appendingPathComponent("HEAD"))

        let backlink = try readSmallText(
            worktreeGitDirectory.appendingPathComponent("gitdir")
        )
        let backlinkURL = URL(fileURLWithPath: backlink, relativeTo: worktreeGitDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard backlinkURL.path == dotGit.standardizedFileURL.path else {
            throw GitWorktreeMetadataError.invalidStructure
        }

        let commonGitDirectory = try resolveGitDirectoryPointer(
            fileURL: worktreeGitDirectory.appendingPathComponent("commondir"),
            prefix: "",
            relativeTo: worktreeGitDirectory
        )
        try requireDirectory(commonGitDirectory)
        try requireDirectory(commonGitDirectory.appendingPathComponent("objects"))
        try requireDirectory(commonGitDirectory.appendingPathComponent("refs"))
        guard worktreeGitDirectory.path.hasPrefix(
            commonGitDirectory.appendingPathComponent("worktrees").path + "/"
        ) else {
            throw GitWorktreeMetadataError.invalidStructure
        }

        let workspacePath = workspace.path
        return [worktreeGitDirectory, commonGitDirectory].compactMap { url in
            let path = url.path
            guard path != workspacePath, !path.hasPrefix(workspacePath + "/") else {
                return nil
            }
            return CommandResourceGrant(path: path, access: .readOnly)
        }
    }

    private static func resolveGitDirectoryPointer(
        fileURL: URL,
        prefix: String,
        relativeTo baseURL: URL
    ) throws -> URL {
        let text = try readSmallText(fileURL)
        guard text.hasPrefix(prefix) else {
            throw GitWorktreeMetadataError.invalidPointer
        }
        let path = String(text.dropFirst(prefix.count))
        guard !path.isEmpty, !path.utf8.contains(0) else {
            throw GitWorktreeMetadataError.invalidPointer
        }
        return URL(fileURLWithPath: path, relativeTo: baseURL)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    private static func readSmallText(_ url: URL) throws -> String {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG else {
            throw GitWorktreeMetadataError.invalidStructure
        }
        guard info.st_size <= 4096 else {
            throw GitWorktreeMetadataError.metadataTooLarge
        }
        let data = try Data(contentsOf: url)
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            throw GitWorktreeMetadataError.invalidPointer
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func requireDirectory(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR else {
            throw GitWorktreeMetadataError.invalidStructure
        }
    }

    private static func requireRegularFile(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG else {
            throw GitWorktreeMetadataError.invalidStructure
        }
    }
}
