import Foundation
import Darwin

public struct WorkspaceTaskStage: Sendable {
    public let workspaceURL: URL
    public let taskRootURL: URL
    public let relativeWorkingDirectory: String
    private let taskCacheURL: URL

    fileprivate init(
        workspaceURL: URL,
        relativeWorkingDirectory: String,
        taskCacheURL: URL
    ) {
        self.workspaceURL = workspaceURL
        self.taskRootURL = workspaceURL.deletingLastPathComponent()
        self.relativeWorkingDirectory = relativeWorkingDirectory
        self.taskCacheURL = taskCacheURL
    }

    public func remove() throws {
        let cachePath = taskCacheURL.standardizedFileURL.resolvingSymlinksInPath().path
        let taskRoot = taskRootURL
            .standardizedFileURL.resolvingSymlinksInPath()
        guard taskRoot.path.hasPrefix(cachePath + "/QwenPrimeTasks/") else {
            throw WorkspaceAccessError.pathTraversal(path: taskRoot.path)
        }
        if FileManager.default.fileExists(atPath: taskRoot.path) {
            try FileManager.default.removeItem(at: taskRoot)
        }
    }
}

public enum WorkspaceTaskStager {
    private static let maxFiles = 1_000
    private static let maxTotalBytes = 10 * 1024 * 1024
    private static let excludedDirectories: Set<String> = [
        ".build", ".cache", ".swiftpm", ".venv", "__pycache__",
        "deriveddata", "node_modules", "venv"
    ]

    public static func stage(
        workspaceURL: URL,
        relativePackagePath: String,
        taskCacheURL: URL,
        id: UUID
    ) async throws -> WorkspaceTaskStage {
        try validateCacheRoot(taskCacheURL, workspaceURL: workspaceURL)
        let service = try ReadOnlyWorkspaceService(
            rootURL: workspaceURL,
            limits: WorkspaceReadLimits(
                maxDirectoryEntries: 1_000,
                maxFileSizeBytes: 1024 * 1024,
                maxFileLineCount: 10_000
            )
        )
        let sourceComponents = try ReadOnlyWorkspaceService
            .validateAndParseDirectoryPath(relativePackagePath)
        let sourceRoot = sourceComponents.joined(separator: "/")
        let relativeTaskRoot = "QwenPrimeTasks/\(id.uuidString)"
        let stageURL = taskCacheURL
            .appendingPathComponent(relativeTaskRoot, isDirectory: true)
            .appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stageURL,
            withIntermediateDirectories: true
        )

        var directories: [(source: String, destination: String)] = [(sourceRoot, "")]
        var directoryIndex = 0
        var copiedFiles = 0
        var copiedBytes = 0

        do {
            while directoryIndex < directories.count {
                try Task.checkCancellation()
                let current = directories[directoryIndex]
                directoryIndex += 1
                let listing = try await service.listDirectory(relativePath: current.source)
                guard !listing.isTruncated else {
                    throw WorkspaceAccessError.invalidLimits(
                        description: "Task package directory exceeds the 1000-entry per-directory limit"
                    )
                }

                for entry in listing.entries {
                    try Task.checkCancellation()
                    guard !ReadOnlyWorkspaceService.isSecretPathComponent(entry.name),
                          !entry.isPackageDirectory,
                          !excludedDirectories.contains(entry.name.lowercased()) else {
                        continue
                    }
                    let destinationPath = current.destination.isEmpty
                        ? entry.name
                        : "\(current.destination)/\(entry.name)"
                    if entry.isDirectory {
                        directories.append((entry.relativePath, destinationPath))
                        continue
                    }
                    guard entry.isRegularFile else {
                        throw WorkspaceAccessError.notRegularFile(path: entry.relativePath)
                    }
                    guard copiedFiles < maxFiles else {
                        throw WorkspaceAccessError.invalidLimits(
                            description: "Task package exceeds the 1000-file limit"
                        )
                    }
                    let read = try await service.readFile(relativePath: entry.relativePath)
                    guard !read.isTruncated else {
                        throw WorkspaceAccessError.invalidLimits(
                            description: "Task package file exceeds staging limits: \(entry.relativePath)"
                        )
                    }
                    copiedBytes += read.byteCount
                    guard copiedBytes <= maxTotalBytes else {
                        throw WorkspaceAccessError.invalidLimits(
                            description: "Task package exceeds the 10 MiB text limit"
                        )
                    }
                    copiedFiles += 1
                    let destinationURL = stageURL.appendingPathComponent(destinationPath)
                    try FileManager.default.createDirectory(
                        at: destinationURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try Data(read.content.utf8).write(to: destinationURL, options: .atomic)
                }
            }
        } catch {
            let stage = WorkspaceTaskStage(
                workspaceURL: stageURL,
                relativeWorkingDirectory: "\(relativeTaskRoot)/workspace",
                taskCacheURL: taskCacheURL
            )
            try? stage.remove()
            throw error
        }

        return WorkspaceTaskStage(
            workspaceURL: stageURL,
            relativeWorkingDirectory: "\(relativeTaskRoot)/workspace",
            taskCacheURL: taskCacheURL
        )
    }

    private static func validateCacheRoot(_ url: URL, workspaceURL: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR else {
            throw WorkspaceAccessError.accessDenied(path: url.path)
        }
        let cachePath = url.standardizedFileURL.resolvingSymlinksInPath().path
        let workspacePath = workspaceURL.standardizedFileURL.resolvingSymlinksInPath().path
        guard cachePath != workspacePath,
              !cachePath.hasPrefix(workspacePath + "/"),
              !workspacePath.hasPrefix(cachePath + "/") else {
            throw WorkspaceAccessError.accessDenied(path: cachePath)
        }
    }
}
