import Foundation
import Darwin

/// Prepares reviewable text mutations and applies only an explicitly approved proposal.
public struct WorkspaceMutationService: Sendable {
    public static let maxChangeSetSize = 8
    public let readService: ReadOnlyWorkspaceService
    public let limits: WorkspaceMutationLimits

    public init(
        readService: ReadOnlyWorkspaceService,
        limits: WorkspaceMutationLimits = .default
    ) {
        self.readService = readService
        self.limits = limits
    }

    public func prepareWrite(
        relativePath: String,
        content: String,
        overwrite: Bool
    ) async throws -> WorkspaceMutationProposal {
        try validateContent(content)
        _ = try ReadOnlyWorkspaceService.validateAndParseFilePath(relativePath)

        let existingContent: String?
        do {
            existingContent = try await readComplete(relativePath: relativePath)
        } catch WorkspaceAccessError.fileNotFound {
            existingContent = nil
        }

        if existingContent != nil && !overwrite {
            throw WorkspaceMutationError.fileAlreadyExists(path: relativePath)
        }

        return WorkspaceMutationProposal(
            operation: .writeFile,
            relativePath: relativePath,
            expectedContent: existingContent,
            proposedContent: content,
            preview: Self.preview(
                relativePath: relativePath,
                original: existingContent,
                proposed: content
            )
        )
    }

    public func preparePatch(
        relativePath: String,
        oldText: String,
        newText: String
    ) async throws -> WorkspaceMutationProposal {
        guard !oldText.isEmpty else {
            throw WorkspaceMutationError.patchTargetNotFound(path: relativePath)
        }
        let original = try await readComplete(relativePath: relativePath)
        let matches = original.ranges(of: oldText)
        guard !matches.isEmpty else {
            throw WorkspaceMutationError.patchTargetNotFound(path: relativePath)
        }
        guard matches.count == 1 else {
            throw WorkspaceMutationError.patchTargetNotUnique(path: relativePath)
        }
        let proposed = original.replacingCharacters(in: matches[0], with: newText)
        try validateContent(proposed)

        return WorkspaceMutationProposal(
            operation: .applyPatch,
            relativePath: relativePath,
            expectedContent: original,
            proposedContent: proposed,
            preview: Self.preview(
                relativePath: relativePath,
                original: original,
                proposed: proposed
            )
        )
    }

    public func prepareChangeSet(
        replacements: [WorkspaceTextReplacement]
    ) async throws -> WorkspaceMutationChangeSet {
        guard !replacements.isEmpty else {
            throw WorkspaceMutationError.emptyChangeSet
        }
        guard replacements.count <= Self.maxChangeSetSize else {
            throw WorkspaceMutationError.tooManyChanges(maximum: Self.maxChangeSetSize)
        }

        var seenPaths: Set<String> = []
        var changes: [WorkspaceMutationProposal] = []
        changes.reserveCapacity(replacements.count)
        for replacement in replacements {
            let parsedPath = try ReadOnlyWorkspaceService.validateAndParseFilePath(replacement.path)
            let canonicalPath = (parsedPath.dirComponents + [parsedPath.fileName])
                .filter { $0 != "." }
                .joined(separator: "/")
            guard seenPaths.insert(canonicalPath).inserted else {
                throw WorkspaceMutationError.duplicateChangePath(path: canonicalPath)
            }
            changes.append(try await preparePatch(
                relativePath: canonicalPath,
                oldText: replacement.oldText,
                newText: replacement.newText
            ))
        }

        let fileCount = changes.count
        let label = "\(fileCount) \(fileCount == 1 ? "file" : "files")"
        let preview = changes.map(\.preview).joined(separator: "\n\n")
        return WorkspaceMutationChangeSet(
            changes: changes,
            reviewProposal: WorkspaceMutationProposal(
                operation: .changeSet,
                relativePath: label,
                expectedContent: nil,
                proposedContent: "",
                preview: preview
            )
        )
    }

    public func apply(_ changeSet: WorkspaceMutationChangeSet) async throws {
        for proposal in changeSet.changes {
            try await preflight(proposal)
        }
        for proposal in changeSet.changes {
            try await apply(proposal)
        }
    }

    public func apply(_ proposal: WorkspaceMutationProposal) async throws {
        try Task.checkCancellation()
        try validateContent(proposal.proposedContent)
        let (dirComponents, fileName) = try ReadOnlyWorkspaceService.validateAndParseFilePath(
            proposal.relativePath
        )

        let currentContent: String?
        do {
            currentContent = try await readComplete(relativePath: proposal.relativePath)
        } catch WorkspaceAccessError.fileNotFound {
            currentContent = nil
        }
        if currentContent == proposal.proposedContent {
            return
        }
        guard currentContent == proposal.expectedContent else {
            throw WorkspaceMutationError.staleProposal(path: proposal.relativePath)
        }

        let rootFd = try readService.openRootDirectory()
        defer { close(rootFd) }
        let dirFd = try openOrCreateDirectoryAtComponents(
            dirComponents,
            fromRoot: rootFd,
            originalPath: proposal.relativePath
        )
        defer {
            if dirFd != rootFd { close(dirFd) }
        }

        let tempName = ".qwen-prime-\(UUID().uuidString).tmp"
        let tempFd = openat(
            dirFd,
            tempName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(S_IRUSR | S_IWUSR)
        )
        guard tempFd >= 0 else {
            throw WorkspaceAccessError.ioError(path: proposal.relativePath, code: errno)
        }

        var shouldRemoveTemp = true
        defer {
            close(tempFd)
            if shouldRemoveTemp { unlinkat(dirFd, tempName, 0) }
        }

        let outputMode: mode_t
        if proposal.expectedContent == nil {
            outputMode = mode_t(S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        } else {
            var targetInfo = stat()
            guard fstatat(dirFd, fileName, &targetInfo, AT_SYMLINK_NOFOLLOW) == 0 else {
                throw WorkspaceMutationError.staleProposal(path: proposal.relativePath)
            }
            outputMode = targetInfo.st_mode & mode_t(0o777)
        }
        guard fchmod(tempFd, outputMode) == 0 else {
            throw WorkspaceAccessError.ioError(path: proposal.relativePath, code: errno)
        }

        try writeAll(proposal.proposedContent, to: tempFd, path: proposal.relativePath)
        guard fsync(tempFd) == 0 else {
            throw WorkspaceAccessError.ioError(path: proposal.relativePath, code: errno)
        }

        try Task.checkCancellation()
        if proposal.expectedContent == nil {
            guard linkat(dirFd, tempName, dirFd, fileName, 0) == 0 else {
                if errno == EEXIST {
                    let collidedContent = try await readComplete(relativePath: proposal.relativePath)
                    if collidedContent == proposal.proposedContent {
                        return
                    }
                    throw WorkspaceMutationError.staleProposal(path: proposal.relativePath)
                }
                throw WorkspaceAccessError.ioError(path: proposal.relativePath, code: errno)
            }
            guard unlinkat(dirFd, tempName, 0) == 0 else {
                throw WorkspaceAccessError.ioError(path: proposal.relativePath, code: errno)
            }
            shouldRemoveTemp = false
        } else {
            let latest = try await readComplete(relativePath: proposal.relativePath)
            if latest == proposal.proposedContent {
                return
            }
            guard latest == proposal.expectedContent else {
                throw WorkspaceMutationError.staleProposal(path: proposal.relativePath)
            }
            guard renameat(dirFd, tempName, dirFd, fileName) == 0 else {
                throw WorkspaceAccessError.ioError(path: proposal.relativePath, code: errno)
            }
            shouldRemoveTemp = false
        }
    }

    private func preflight(_ proposal: WorkspaceMutationProposal) async throws {
        try Task.checkCancellation()
        let currentContent: String?
        do {
            currentContent = try await readComplete(relativePath: proposal.relativePath)
        } catch WorkspaceAccessError.fileNotFound {
            currentContent = nil
        }
        guard currentContent == proposal.expectedContent || currentContent == proposal.proposedContent else {
            throw WorkspaceMutationError.staleProposal(path: proposal.relativePath)
        }
    }

    private func validateContent(_ content: String) throws {
        guard limits.maxWriteBytes > 0 else {
            throw WorkspaceMutationError.invalidLimits
        }
        guard content.utf8.count <= limits.maxWriteBytes else {
            throw WorkspaceMutationError.contentTooLarge(maxBytes: limits.maxWriteBytes)
        }
        guard !content.utf8.contains(0) else {
            throw WorkspaceAccessError.binaryFileNotSupported(path: "<proposed content>")
        }
    }

    private func readComplete(relativePath: String) async throws -> String {
        let result = try await readService.readFile(relativePath: relativePath)
        guard !result.isTruncated else {
            throw WorkspaceMutationError.sourceTruncated(path: relativePath)
        }
        return result.content
    }

    private func writeAll(_ content: String, to fd: Int32, path: String) throws {
        let bytes = Array(content.utf8)
        var offset = 0
        while offset < bytes.count {
            try Task.checkCancellation()
            let written = bytes.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return 0 }
                return Darwin.write(fd, base.advanced(by: offset), buffer.count - offset)
            }
            if written < 0 {
                if errno == EINTR { continue }
                throw WorkspaceAccessError.ioError(path: path, code: errno)
            }
            offset += written
        }
    }

    private func openOrCreateDirectoryAtComponents(
        _ components: [String],
        fromRoot rootFd: Int32,
        originalPath: String
    ) throws -> Int32 {
        var currentFd = rootFd

        for component in components {
            var info = stat()
            if fstatat(currentFd, component, &info, AT_SYMLINK_NOFOLLOW) != 0 {
                let inspectionError = errno
                guard inspectionError == ENOENT else {
                    if currentFd != rootFd { close(currentFd) }
                    if inspectionError == EACCES {
                        throw WorkspaceAccessError.accessDenied(path: originalPath)
                    }
                    throw WorkspaceAccessError.ioError(path: originalPath, code: inspectionError)
                }
                if mkdirat(currentFd, component, mode_t(0o755)) != 0, errno != EEXIST {
                    let creationError = errno
                    if currentFd != rootFd { close(currentFd) }
                    if creationError == EACCES {
                        throw WorkspaceAccessError.accessDenied(path: originalPath)
                    }
                    throw WorkspaceAccessError.ioError(path: originalPath, code: creationError)
                }
                guard fstatat(currentFd, component, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
                    let verificationError = errno
                    if currentFd != rootFd { close(currentFd) }
                    throw WorkspaceAccessError.ioError(path: originalPath, code: verificationError)
                }
            }

            if (info.st_mode & S_IFMT) == S_IFLNK {
                if currentFd != rootFd { close(currentFd) }
                throw WorkspaceAccessError.symlinkNotAllowed(path: originalPath)
            }
            guard (info.st_mode & S_IFMT) == S_IFDIR else {
                if currentFd != rootFd { close(currentFd) }
                throw WorkspaceAccessError.fileNotFound(path: originalPath)
            }

            let nextFd = openat(
                currentFd,
                component,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
            guard nextFd >= 0 else {
                let openError = errno
                if currentFd != rootFd { close(currentFd) }
                if openError == ELOOP {
                    throw WorkspaceAccessError.symlinkNotAllowed(path: originalPath)
                }
                throw WorkspaceAccessError.accessDenied(path: originalPath)
            }
            if currentFd != rootFd { close(currentFd) }
            currentFd = nextFd
        }

        return currentFd
    }

    static func preview(relativePath: String, original: String?, proposed: String) -> String {
        let oldHeader = original == nil ? "/dev/null" : relativePath
        let oldLines = original.map(Self.lines) ?? []
        let newLines = Self.lines(proposed)
        var output = ["--- \(oldHeader)", "+++ \(relativePath)"]
        output.append(contentsOf: oldLines.map { "-\($0)" })
        output.append(contentsOf: newLines.map { "+\($0)" })
        return output.joined(separator: "\n")
    }

    private static func lines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}

private extension String {
    func ranges(of substring: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var searchStart = startIndex
        while searchStart < endIndex,
              let range = range(of: substring, range: searchStart..<endIndex) {
            result.append(range)
            searchStart = range.upperBound
        }
        return result
    }
}
