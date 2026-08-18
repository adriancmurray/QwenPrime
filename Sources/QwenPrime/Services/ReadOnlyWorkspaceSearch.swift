import Foundation

extension ReadOnlyWorkspaceService {
    private static let maxSearchResults = 100
    private static let maxSearchFiles = 500
    private static let maxSearchDirectories = 500
    private static let maxSearchChunks = 2_000
    private static let maxSearchLineCharacters = 500
    private static let excludedSearchDirectories: Set<String> = [
        ".build", ".cache", ".swiftpm", ".venv", "__pycache__",
        "deriveddata", "node_modules", "venv"
    ]

    public func findFiles(
        query: String,
        relativePath: String? = nil,
        caseSensitive: Bool = false
    ) async throws -> WorkspaceFileSearchResult {
        try Self.validateSearchQuery(query)
        let walk = try await walkFiles(relativePath: relativePath)
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var matches: [WorkspaceFileMatch] = []
        var isTruncated = walk.isTruncated

        for path in walk.paths where URL(fileURLWithPath: path).lastPathComponent.range(
            of: query,
            options: options
        ) != nil {
            try Task.checkCancellation()
            guard matches.count < Self.maxSearchResults else {
                isTruncated = true
                break
            }
            matches.append(WorkspaceFileMatch(relativePath: path))
        }

        return WorkspaceFileSearchResult(
            query: query,
            matches: matches,
            scannedFiles: walk.paths.count,
            isTruncated: isTruncated
        )
    }

    public func searchText(
        query: String,
        relativePath: String? = nil,
        caseSensitive: Bool = true
    ) async throws -> WorkspaceTextSearchResult {
        try Self.validateSearchQuery(query)
        let walk = try await walkFiles(relativePath: relativePath)
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var matches: [WorkspaceTextMatch] = []
        var scannedFiles = 0
        var isTruncated = walk.isTruncated
        var remainingChunks = Self.maxSearchChunks

        searchLoop: for path in walk.paths {
            try Task.checkCancellation()
            var startLine = 1
            var didScanFile = false

            while remainingChunks > 0 {
                try Task.checkCancellation()
                remainingChunks -= 1
                let read: WorkspaceFileRead
                do {
                    read = try await readFile(
                        relativePath: path,
                        startLine: startLine,
                        endLine: startLine + limits.maxFileLineCount - 1
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    break
                }
                guard !read.content.isEmpty else { break }
                if !didScanFile {
                    scannedFiles += 1
                    didScanFile = true
                }

                let lines = read.content.split(
                    separator: "\n",
                    omittingEmptySubsequences: false
                )
                for (offset, line) in lines.enumerated()
                    where line.range(of: query, options: options) != nil {
                    guard matches.count < Self.maxSearchResults else {
                        isTruncated = true
                        break searchLoop
                    }
                    matches.append(WorkspaceTextMatch(
                        relativePath: path,
                        lineNumber: startLine + offset,
                        line: String(line.prefix(Self.maxSearchLineCharacters))
                    ))
                }

                if read.isTruncated {
                    isTruncated = true
                    break
                }
                guard read.lineCount >= limits.maxFileLineCount else { break }
                startLine += limits.maxFileLineCount
            }

            if remainingChunks == 0 {
                isTruncated = true
                break
            }
        }

        return WorkspaceTextSearchResult(
            query: query,
            matches: matches,
            scannedFiles: scannedFiles,
            isTruncated: isTruncated
        )
    }

    private static func validateSearchQuery(_ query: String) throws {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...256).contains(query.utf8.count),
              !query.utf8.contains(0) else {
            throw WorkspaceAccessError.invalidSearchQuery
        }
    }

    private func walkFiles(relativePath: String?) async throws -> WorkspaceFileWalk {
        var directories = [relativePath]
        var directoryIndex = 0
        var paths: [String] = []
        paths.reserveCapacity(Self.maxSearchFiles)
        var isTruncated = false

        while directoryIndex < directories.count {
            try Task.checkCancellation()
            if paths.count >= Self.maxSearchFiles {
                isTruncated = true
                break
            }
            let listing = try await listDirectory(relativePath: directories[directoryIndex])
            directoryIndex += 1
            isTruncated = isTruncated || listing.isTruncated

            for entry in listing.entries {
                try Task.checkCancellation()
                guard !Self.isSecretPathComponent(entry.name),
                      !entry.isPackageDirectory,
                      !Self.excludedSearchDirectories.contains(entry.name.lowercased()) else {
                    continue
                }
                if entry.isDirectory {
                    guard directories.count < Self.maxSearchDirectories else {
                        isTruncated = true
                        continue
                    }
                    directories.append(entry.relativePath)
                } else if entry.isRegularFile && paths.count < Self.maxSearchFiles {
                    paths.append(entry.relativePath)
                } else if entry.isRegularFile {
                    isTruncated = true
                }
            }
        }

        return WorkspaceFileWalk(paths: paths.sorted(), isTruncated: isTruncated)
    }
}

private struct WorkspaceFileWalk {
    let paths: [String]
    let isTruncated: Bool
}
