import Foundation

/// Resource limits applied to workspace directory listing and file reading operations.
public struct WorkspaceReadLimits: Sendable, Equatable, Hashable, Codable {
    public var maxDirectoryEntries: Int
    public var maxFileSizeBytes: Int
    public var maxFileLineCount: Int

    public static let `default` = WorkspaceReadLimits(
        maxDirectoryEntries: 200,
        maxFileSizeBytes: 64 * 1024,
        maxFileLineCount: 500
    )

    public init(
        maxDirectoryEntries: Int = 200,
        maxFileSizeBytes: Int = 64 * 1024,
        maxFileLineCount: Int = 500
    ) {
        self.maxDirectoryEntries = maxDirectoryEntries
        self.maxFileSizeBytes = maxFileSizeBytes
        self.maxFileLineCount = maxFileLineCount
    }
}

/// Metadata describing a single file or directory entry within a workspace.
public struct WorkspaceEntry: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var id: String { relativePath }
    public var name: String
    public var relativePath: String
    public var isDirectory: Bool
    public var isPackageDirectory: Bool
    public var isRegularFile: Bool
    public var sizeBytes: Int64?

    public init(
        name: String,
        relativePath: String,
        isDirectory: Bool,
        isPackageDirectory: Bool,
        isRegularFile: Bool = false,
        sizeBytes: Int64? = nil
    ) {
        self.name = name
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.isPackageDirectory = isPackageDirectory
        self.isRegularFile = isRegularFile
        self.sizeBytes = sizeBytes
    }
}

/// Result of listing the contents of a directory in the workspace.
public struct WorkspaceDirectoryListing: Sendable, Equatable, Hashable, Codable {
    public var relativePath: String
    public var entries: [WorkspaceEntry]
    public var isTruncated: Bool

    public init(
        relativePath: String,
        entries: [WorkspaceEntry],
        isTruncated: Bool
    ) {
        self.relativePath = relativePath
        self.entries = entries
        self.isTruncated = isTruncated
    }
}

/// Result of reading a text file in the workspace.
public struct WorkspaceFileRead: Sendable, Equatable, Hashable, Codable {
    public var relativePath: String
    public var content: String
    public var byteCount: Int
    public var lineCount: Int
    public var isTruncated: Bool

    public init(
        relativePath: String,
        content: String,
        byteCount: Int,
        lineCount: Int,
        isTruncated: Bool
    ) {
        self.relativePath = relativePath
        self.content = content
        self.byteCount = byteCount
        self.lineCount = lineCount
        self.isTruncated = isTruncated
    }
}

public struct WorkspaceFileMatch: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var id: String { relativePath }
    public var relativePath: String

    public init(relativePath: String) {
        self.relativePath = relativePath
    }
}

public struct WorkspaceFileSearchResult: Sendable, Equatable, Hashable, Codable {
    public var query: String
    public var matches: [WorkspaceFileMatch]
    public var scannedFiles: Int
    public var isTruncated: Bool

    public init(
        query: String,
        matches: [WorkspaceFileMatch],
        scannedFiles: Int,
        isTruncated: Bool
    ) {
        self.query = query
        self.matches = matches
        self.scannedFiles = scannedFiles
        self.isTruncated = isTruncated
    }
}

public struct WorkspaceTextMatch: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var id: String { "\(relativePath):\(lineNumber)" }
    public var relativePath: String
    public var lineNumber: Int
    public var line: String

    public init(relativePath: String, lineNumber: Int, line: String) {
        self.relativePath = relativePath
        self.lineNumber = lineNumber
        self.line = line
    }
}

public struct WorkspaceTextSearchResult: Sendable, Equatable, Hashable, Codable {
    public var query: String
    public var matches: [WorkspaceTextMatch]
    public var scannedFiles: Int
    public var isTruncated: Bool

    public init(
        query: String,
        matches: [WorkspaceTextMatch],
        scannedFiles: Int,
        isTruncated: Bool
    ) {
        self.query = query
        self.matches = matches
        self.scannedFiles = scannedFiles
        self.isTruncated = isTruncated
    }
}

public struct WorkspaceMutationLimits: Sendable, Equatable, Hashable, Codable {
    public var maxWriteBytes: Int

    public static let `default` = WorkspaceMutationLimits(maxWriteBytes: 64 * 1024)

    public init(maxWriteBytes: Int = 64 * 1024) {
        self.maxWriteBytes = maxWriteBytes
    }
}

public enum WorkspaceMutationOperation: String, Sendable, Equatable, Hashable, Codable {
    case writeFile
    case applyPatch
    case changeSet
}

public struct WorkspaceMutationProposal: Sendable, Equatable, Hashable, Codable {
    public var operation: WorkspaceMutationOperation
    public var relativePath: String
    public var expectedContent: String?
    public var proposedContent: String
    public var preview: String

    public init(
        operation: WorkspaceMutationOperation,
        relativePath: String,
        expectedContent: String?,
        proposedContent: String,
        preview: String
    ) {
        self.operation = operation
        self.relativePath = relativePath
        self.expectedContent = expectedContent
        self.proposedContent = proposedContent
        self.preview = preview
    }
}

public struct WorkspaceTextReplacement: Sendable, Equatable, Hashable, Codable {
    public var path: String
    public var oldText: String
    public var newText: String

    public init(path: String, oldText: String, newText: String) {
        self.path = path
        self.oldText = oldText
        self.newText = newText
    }
}

public struct WorkspaceMutationChangeSet: Sendable, Equatable, Hashable {
    public var changes: [WorkspaceMutationProposal]
    public var reviewProposal: WorkspaceMutationProposal

    public init(changes: [WorkspaceMutationProposal], reviewProposal: WorkspaceMutationProposal) {
        self.changes = changes
        self.reviewProposal = reviewProposal
    }
}

public enum ToolApprovalState: String, Sendable, Equatable, Hashable, Codable {
    case pending
    case applying
    case approved
    case rejected
    case failed
}

public enum WorkspaceMutationError: Error, Sendable, Equatable, LocalizedError {
    case invalidLimits
    case contentTooLarge(maxBytes: Int)
    case sourceTruncated(path: String)
    case fileAlreadyExists(path: String)
    case patchTargetNotFound(path: String)
    case patchTargetNotUnique(path: String)
    case staleProposal(path: String)
    case emptyChangeSet
    case tooManyChanges(maximum: Int)
    case duplicateChangePath(path: String)

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            return "Workspace mutation limits must be strictly positive."
        case .contentTooLarge(let maxBytes):
            return "Proposed content exceeds the \(maxBytes)-byte workspace mutation limit."
        case .sourceTruncated(let path):
            return "The complete source file cannot be reviewed within workspace limits: \(path)"
        case .fileAlreadyExists(let path):
            return "File already exists and overwrite was not requested: \(path)"
        case .patchTargetNotFound(let path):
            return "Patch text was not found in: \(path)"
        case .patchTargetNotUnique(let path):
            return "Patch text must match exactly once in: \(path)"
        case .staleProposal(let path):
            return "The file changed after the proposal was reviewed: \(path)"
        case .emptyChangeSet:
            return "A workspace change set must contain at least one replacement."
        case .tooManyChanges(let maximum):
            return "A workspace change set may contain at most \(maximum) replacements."
        case .duplicateChangePath(let path):
            return "A workspace change set may modify each file only once: \(path)"
        }
    }
}

/// Retains at most `maxEntries` in globally lexicographical order while tracking total count and truncation status.
public struct BoundedWorkspaceEntrySelector: Sendable {
    public let maxEntries: Int
    public private(set) var totalCount: Int = 0
    public private(set) var selectedEntries: [WorkspaceEntry] = []

    public var isTruncated: Bool {
        totalCount > maxEntries
    }

    public init(maxEntries: Int) {
        self.maxEntries = max(0, maxEntries)
        self.selectedEntries.reserveCapacity(min(max(0, maxEntries), 256))
    }

    public mutating func insert(_ entry: WorkspaceEntry) {
        totalCount += 1
        guard maxEntries > 0 else { return }

        if selectedEntries.count < maxEntries {
            let index = binarySearchInsertionIndex(for: entry)
            selectedEntries.insert(entry, at: index)
        } else if let last = selectedEntries.last, isOrderedBefore(entry, last) {
            selectedEntries.removeLast()
            let index = binarySearchInsertionIndex(for: entry)
            selectedEntries.insert(entry, at: index)
        }
    }

    private func isOrderedBefore(_ a: WorkspaceEntry, _ b: WorkspaceEntry) -> Bool {
        if a.name != b.name {
            return a.name < b.name
        }
        return a.relativePath < b.relativePath
    }

    private func binarySearchInsertionIndex(for entry: WorkspaceEntry) -> Int {
        var low = 0
        var high = selectedEntries.count
        while low < high {
            let mid = (low + high) / 2
            if isOrderedBefore(selectedEntries[mid], entry) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}

/// Typed errors encountered during workspace access and traversal.
public enum WorkspaceAccessError: Error, Sendable, Equatable, LocalizedError {
    case workspaceRootNotFound(path: String)
    case workspaceRootNotDirectory(path: String)
    case workspaceRootIsSymlink(path: String)
    case pathTraversal(path: String)
    case symlinkNotAllowed(path: String)
    case binaryFileNotSupported(path: String)
    case isDirectory(path: String)
    case opaquePackageRestricted(path: String)
    case secretPathRestricted(path: String)
    case fileNotFound(path: String)
    case notRegularFile(path: String)
    case accessDenied(path: String)
    case invalidPath(path: String)
    case invalidLineRange(startLine: Int?, endLine: Int?)
    case ioError(path: String, code: Int32)
    case invalidLimits(description: String)
    case invalidSearchQuery

    public var errorDescription: String? {
        switch self {
        case .workspaceRootNotFound(let path):
            return "Workspace root directory not found: \(path)"
        case .workspaceRootNotDirectory(let path):
            return "Workspace root is not a directory: \(path)"
        case .workspaceRootIsSymlink(let path):
            return "Workspace root is a symbolic link: \(path)"
        case .pathTraversal(let path):
            return "Path traversal rejected: \(path)"
        case .symlinkNotAllowed(let path):
            return "Symbolic link not allowed: \(path)"
        case .binaryFileNotSupported(let path):
            return "Binary or non-UTF-8 file content is not supported: \(path)"
        case .isDirectory(let path):
            return "Path is a directory: \(path)"
        case .opaquePackageRestricted(let path):
            return "Cannot descend into opaque package directory: \(path)"
        case .secretPathRestricted(let path):
            return "Access to secret path is restricted: \(path)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .notRegularFile(let path):
            return "Not a regular file: \(path)"
        case .accessDenied(let path):
            return "Access denied: \(path)"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .invalidLineRange(let startLine, let endLine):
            return "Invalid line range: start_line=\(startLine.map(String.init) ?? "nil"), end_line=\(endLine.map(String.init) ?? "nil")"
        case .ioError(let path, let code):
            return "Filesystem I/O error (\(code)) at: \(path)"
        case .invalidLimits(let description):
            return "Invalid workspace read limits: \(description)"
        case .invalidSearchQuery:
            return "Search query must contain non-whitespace text between 1 and 256 UTF-8 bytes."
        }
    }
}
