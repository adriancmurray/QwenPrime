import Foundation
import Darwin

/// Thread-safe, non-mutating service providing bounded read-only access to a workspace directory.
public struct ReadOnlyWorkspaceService: Sendable {
    public let rootURL: URL
    public let limits: WorkspaceReadLimits

    public init(rootURL: URL, limits: WorkspaceReadLimits = .default) throws {
        guard limits.maxDirectoryEntries > 0,
              limits.maxFileSizeBytes > 0,
              limits.maxFileLineCount > 0 else {
            throw WorkspaceAccessError.invalidLimits(description: "Limits must be strictly positive")
        }
        self.rootURL = rootURL
        self.limits = limits
        try Self.validateRoot(at: rootURL)
    }

    /// Validates that the workspace root exists, is a directory, and is not a symbolic link.
    static func validateRoot(at url: URL) throws {
        let path = url.path
        var st = stat()
        if lstat(path, &st) != 0 {
            throw WorkspaceAccessError.workspaceRootNotFound(path: path)
        }
        if (st.st_mode & S_IFMT) == S_IFLNK {
            throw WorkspaceAccessError.workspaceRootIsSymlink(path: path)
        }
        if (st.st_mode & S_IFMT) != S_IFDIR {
            throw WorkspaceAccessError.workspaceRootNotDirectory(path: path)
        }
    }

    /// Checks whether a path component represents a forbidden secret-bearing file or directory.
    static func isSecretPathComponent(_ component: String) -> Bool {
        let lower = component.lowercased()
        if lower == ".git" {
            return true
        }
        if lower == ".env" || lower.hasPrefix(".env.") {
            if lower.hasSuffix(".example") || lower.hasSuffix(".sample") || lower.hasSuffix(".template") {
                return false
            }
            return true
        }
        if lower.hasSuffix(".pem") || lower.hasSuffix(".key") {
            return true
        }
        if lower == "id_rsa" || lower == "id_ed25519" || lower == "id_dsa" || lower == "id_ecdsa" {
            return true
        }
        return false
    }

    /// Checks whether a name matches an opaque package directory (.app, .bundle, .framework).
    static func isOpaquePackageName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".app") || lower.hasSuffix(".bundle") || lower.hasSuffix(".framework")
    }

    /// Validates and decomposes a relative file path into ancestor directory components and the target filename.
    static func validateAndParseFilePath(_ path: String) throws -> (dirComponents: [String], fileName: String) {
        if path.utf8.contains(0) {
            throw WorkspaceAccessError.invalidPath(path: path)
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw WorkspaceAccessError.invalidPath(path: path)
        }
        if path.hasPrefix("/") {
            throw WorkspaceAccessError.pathTraversal(path: path)
        }
        if path == "." || path == "./" {
            throw WorkspaceAccessError.isDirectory(path: path)
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if components.isEmpty {
            throw WorkspaceAccessError.invalidPath(path: path)
        }

        for comp in components {
            if comp == ".." {
                throw WorkspaceAccessError.pathTraversal(path: path)
            }
            if isSecretPathComponent(comp) {
                throw WorkspaceAccessError.secretPathRestricted(path: path)
            }
            if isOpaquePackageName(comp) {
                throw WorkspaceAccessError.opaquePackageRestricted(path: path)
            }
        }

        let fileName = components[components.count - 1]
        let dirComponents = Array(components.dropLast())
        return (dirComponents, fileName)
    }

    /// Validates and decomposes a relative directory path into its components.
    static func validateAndParseDirectoryPath(_ path: String?) throws -> [String] {
        guard let path = path else {
            return []
        }
        if path.utf8.contains(0) {
            throw WorkspaceAccessError.invalidPath(path: path)
        }
        if path.hasPrefix("/") {
            throw WorkspaceAccessError.pathTraversal(path: path)
        }
        if path == "." || path == "./" || path.isEmpty {
            return []
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if components.isEmpty {
            return []
        }

        for comp in components {
            if comp == ".." {
                throw WorkspaceAccessError.pathTraversal(path: path)
            }
            if isSecretPathComponent(comp) {
                throw WorkspaceAccessError.secretPathRestricted(path: path)
            }
            if isOpaquePackageName(comp) {
                throw WorkspaceAccessError.opaquePackageRestricted(path: path)
            }
        }

        return components
    }

    /// Trims trailing incomplete UTF-8 sequence bytes resulting from buffer size truncation.
    static func trimIncompleteTrailingUTF8(bytes: [UInt8]) -> ([UInt8], Bool) {
        guard !bytes.isEmpty else { return (bytes, false) }
        let count = bytes.count

        let b1 = bytes[count - 1]
        if (b1 & 0xE0) == 0xC0 {
            return (Array(bytes.dropLast(1)), true)
        }
        if (b1 & 0xF0) == 0xE0 {
            return (Array(bytes.dropLast(1)), true)
        }
        if (b1 & 0xF8) == 0xF0 {
            return (Array(bytes.dropLast(1)), true)
        }

        if count >= 2 {
            let b2 = bytes[count - 2]
            if (b2 & 0xF0) == 0xE0 {
                return (Array(bytes.dropLast(2)), true)
            }
            if (b2 & 0xF8) == 0xF0 {
                return (Array(bytes.dropLast(2)), true)
            }
        }

        if count >= 3 {
            let b3 = bytes[count - 3]
            if (b3 & 0xF8) == 0xF0 {
                return (Array(bytes.dropLast(3)), true)
            }
        }

        return (bytes, false)
    }

    /// Opens the workspace root directory descriptor with O_NOFOLLOW.
    func openRootDirectory() throws -> Int32 {
        let rootPath = rootURL.path
        var st = stat()
        if lstat(rootPath, &st) != 0 {
            throw WorkspaceAccessError.workspaceRootNotFound(path: rootPath)
        }
        if (st.st_mode & S_IFMT) == S_IFLNK {
            throw WorkspaceAccessError.workspaceRootIsSymlink(path: rootPath)
        }
        if (st.st_mode & S_IFMT) != S_IFDIR {
            throw WorkspaceAccessError.workspaceRootNotDirectory(path: rootPath)
        }

        let rootFd = open(rootPath, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard rootFd >= 0 else {
            if errno == ELOOP {
                throw WorkspaceAccessError.workspaceRootIsSymlink(path: rootPath)
            }
            if errno == ENOENT {
                throw WorkspaceAccessError.workspaceRootNotFound(path: rootPath)
            }
            if errno == ENOTDIR {
                throw WorkspaceAccessError.workspaceRootNotDirectory(path: rootPath)
            }
            throw WorkspaceAccessError.accessDenied(path: rootPath)
        }
        return rootFd
    }

    /// Traverses directory components from rootFd with O_NOFOLLOW and AT_SYMLINK_NOFOLLOW.
    func openDirectoryAtComponents(_ components: [String], fromRoot rootFd: Int32, originalPath: String) throws -> Int32 {
        var currentFd = rootFd

        for comp in components {
            var st = stat()
            if fstatat(currentFd, comp, &st, AT_SYMLINK_NOFOLLOW) != 0 {
                if currentFd != rootFd { close(currentFd) }
                if errno == ENOENT {
                    throw WorkspaceAccessError.fileNotFound(path: originalPath)
                }
                if errno == EACCES {
                    throw WorkspaceAccessError.accessDenied(path: originalPath)
                }
                throw WorkspaceAccessError.ioError(path: originalPath, code: errno)
            }

            if (st.st_mode & S_IFMT) == S_IFLNK {
                if currentFd != rootFd { close(currentFd) }
                throw WorkspaceAccessError.symlinkNotAllowed(path: originalPath)
            }
            if (st.st_mode & S_IFMT) != S_IFDIR {
                if currentFd != rootFd { close(currentFd) }
                throw WorkspaceAccessError.fileNotFound(path: originalPath)
            }

            let nextFd = openat(currentFd, comp, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            if nextFd < 0 {
                let err = errno
                if currentFd != rootFd { close(currentFd) }
                if err == ELOOP {
                    throw WorkspaceAccessError.symlinkNotAllowed(path: originalPath)
                }
                if err == ENOENT {
                    throw WorkspaceAccessError.fileNotFound(path: originalPath)
                }
                throw WorkspaceAccessError.accessDenied(path: originalPath)
            }

            if currentFd != rootFd {
                close(currentFd)
            }
            currentFd = nextFd
        }

        return currentFd
    }

    /// Non-recursively lists the contents of a directory in the workspace.
    public func listDirectory(relativePath: String? = nil) async throws -> WorkspaceDirectoryListing {
        try Task.checkCancellation()

        let originalPath = relativePath ?? ""
        let components = try Self.validateAndParseDirectoryPath(relativePath)
        let canonicalRelativePath = components.joined(separator: "/")

        let rootFd = try openRootDirectory()
        defer { close(rootFd) }

        let targetDirFd = try openDirectoryAtComponents(components, fromRoot: rootFd, originalPath: originalPath)
        defer {
            if targetDirFd != rootFd {
                close(targetDirFd)
            }
        }

        let dupFd = dup(targetDirFd)
        guard dupFd >= 0 else {
            throw WorkspaceAccessError.ioError(path: originalPath, code: errno)
        }
        guard let dirStream = fdopendir(dupFd) else {
            close(dupFd)
            throw WorkspaceAccessError.ioError(path: originalPath, code: errno)
        }
        defer { closedir(dirStream) }

        var selector = BoundedWorkspaceEntrySelector(maxEntries: limits.maxDirectoryEntries)

        while let entryPtr = readdir(dirStream) {
            try Task.checkCancellation()

            let name = withUnsafePointer(to: &entryPtr.pointee.d_name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 1) { cStr in
                    String(cString: cStr)
                }
            }

            if name == "." || name == ".." {
                continue
            }

            var st = stat()
            if fstatat(targetDirFd, name, &st, AT_SYMLINK_NOFOLLOW) != 0 {
                continue
            }

            let entryRelativePath = canonicalRelativePath.isEmpty ? name : "\(canonicalRelativePath)/\(name)"
            let mode = st.st_mode & S_IFMT

            let isDir = (mode == S_IFDIR)
            let isPackage = isDir && Self.isOpaquePackageName(name)
            let sizeBytes: Int64? = isDir ? nil : Int64(st.st_size)

            selector.insert(WorkspaceEntry(
                name: name,
                relativePath: entryRelativePath,
                isDirectory: isDir,
                isPackageDirectory: isPackage,
                isRegularFile: mode == S_IFREG,
                sizeBytes: sizeBytes
            ))
        }

        try Task.checkCancellation()

        return WorkspaceDirectoryListing(
            relativePath: canonicalRelativePath,
            entries: selector.selectedEntries,
            isTruncated: selector.isTruncated
        )
    }

    /// Reads bounded UTF-8 text from a regular file within the workspace.
    public func readFile(
        relativePath: String,
        startLine: Int? = nil,
        endLine: Int? = nil
    ) async throws -> WorkspaceFileRead {
        try Task.checkCancellation()

        let firstLine = startLine ?? 1
        guard firstLine >= 1,
              endLine.map({ $0 >= firstLine }) ?? true else {
            throw WorkspaceAccessError.invalidLineRange(
                startLine: startLine,
                endLine: endLine
            )
        }

        let (dirComponents, fileName) = try Self.validateAndParseFilePath(relativePath)

        let rootFd = try openRootDirectory()
        defer { close(rootFd) }

        let dirFd = try openDirectoryAtComponents(dirComponents, fromRoot: rootFd, originalPath: relativePath)
        defer {
            if dirFd != rootFd {
                close(dirFd)
            }
        }

        var st = stat()
        if fstatat(dirFd, fileName, &st, AT_SYMLINK_NOFOLLOW) != 0 {
            if errno == ENOENT {
                throw WorkspaceAccessError.fileNotFound(path: relativePath)
            }
            if errno == EACCES {
                throw WorkspaceAccessError.accessDenied(path: relativePath)
            }
            throw WorkspaceAccessError.ioError(path: relativePath, code: errno)
        }

        let mode = st.st_mode & S_IFMT
        if mode == S_IFLNK {
            throw WorkspaceAccessError.symlinkNotAllowed(path: relativePath)
        }
        if mode == S_IFDIR {
            throw WorkspaceAccessError.isDirectory(path: relativePath)
        }
        if mode != S_IFREG {
            throw WorkspaceAccessError.notRegularFile(path: relativePath)
        }

        let fileFd = openat(dirFd, fileName, O_NONBLOCK | O_NOFOLLOW | O_RDONLY | O_CLOEXEC)
        guard fileFd >= 0 else {
            let err = errno
            if err == ELOOP {
                throw WorkspaceAccessError.symlinkNotAllowed(path: relativePath)
            }
            if err == ENOENT {
                throw WorkspaceAccessError.fileNotFound(path: relativePath)
            }
            if err == EISDIR {
                throw WorkspaceAccessError.isDirectory(path: relativePath)
            }
            if err == EACCES {
                throw WorkspaceAccessError.accessDenied(path: relativePath)
            }
            throw WorkspaceAccessError.accessDenied(path: relativePath)
        }
        defer { close(fileFd) }

        var openSt = stat()
        if fstat(fileFd, &openSt) != 0 {
            throw WorkspaceAccessError.ioError(path: relativePath, code: errno)
        }

        let openMode = openSt.st_mode & S_IFMT
        if openMode == S_IFLNK {
            throw WorkspaceAccessError.symlinkNotAllowed(path: relativePath)
        }
        if openMode == S_IFDIR {
            throw WorkspaceAccessError.isDirectory(path: relativePath)
        }
        if openMode != S_IFREG {
            throw WorkspaceAccessError.notRegularFile(path: relativePath)
        }

        if openSt.st_dev != st.st_dev || openSt.st_ino != st.st_ino {
            throw WorkspaceAccessError.accessDenied(path: relativePath)
        }

        let maxBytes = limits.maxFileSizeBytes
        var output = [UInt8]()
        output.reserveCapacity(min(maxBytes, 64 * 1024))
        var readBuffer = [UInt8](repeating: 0, count: 8 * 1024)
        var currentLine = 1
        var completedSelectedLines = 0
        var lineLimitReached = false
        var isTruncated = false
        var reachedRequestedEnd = false
        var reachedEOF = false
        var utf8ContinuationBytes = 0
        var nextContinuationRange: ClosedRange<UInt8>?

        func acceptsUTF8Byte(_ byte: UInt8) -> Bool {
            if utf8ContinuationBytes > 0 {
                let allowed = nextContinuationRange ?? 0x80...0xBF
                guard allowed.contains(byte) else { return false }
                utf8ContinuationBytes -= 1
                nextContinuationRange = nil
                return true
            }
            switch byte {
            case 0x00...0x7F:
                return true
            case 0xC2...0xDF:
                utf8ContinuationBytes = 1
            case 0xE0:
                utf8ContinuationBytes = 2
                nextContinuationRange = 0xA0...0xBF
            case 0xE1...0xEC, 0xEE...0xEF:
                utf8ContinuationBytes = 2
            case 0xED:
                utf8ContinuationBytes = 2
                nextContinuationRange = 0x80...0x9F
            case 0xF0:
                utf8ContinuationBytes = 3
                nextContinuationRange = 0x90...0xBF
            case 0xF1...0xF3:
                utf8ContinuationBytes = 3
            case 0xF4:
                utf8ContinuationBytes = 3
                nextContinuationRange = 0x80...0x8F
            default:
                return false
            }
            return true
        }

        readLoop: while true {
            try Task.checkCancellation()
            let bytesRead = readBuffer.withUnsafeMutableBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else { return -1 }
                return read(fileFd, baseAddress, rawBuffer.count)
            }

            if bytesRead < 0 {
                if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
                throw WorkspaceAccessError.ioError(path: relativePath, code: errno)
            }
            if bytesRead == 0 {
                reachedEOF = true
                break
            }

            for byte in readBuffer.prefix(bytesRead) {
                if byte == 0 || !acceptsUTF8Byte(byte) {
                    throw WorkspaceAccessError.binaryFileNotSupported(path: relativePath)
                }
                if lineLimitReached {
                    if output.last == 0x0A {
                        output.removeLast()
                    }
                    isTruncated = true
                    break readLoop
                }

                let isSelected = currentLine >= firstLine
                    && (endLine.map { currentLine <= $0 } ?? true)
                if isSelected {
                    guard output.count < maxBytes else {
                        isTruncated = true
                        break readLoop
                    }
                    output.append(byte)
                }

                if byte == 0x0A {
                    if isSelected {
                        completedSelectedLines += 1
                    }
                    if endLine == currentLine {
                        reachedRequestedEnd = true
                        break readLoop
                    }
                    if completedSelectedLines >= limits.maxFileLineCount {
                        lineLimitReached = true
                    }
                    currentLine += 1
                }
            }
        }

        try Task.checkCancellation()
        if reachedEOF && utf8ContinuationBytes != 0 {
            throw WorkspaceAccessError.binaryFileNotSupported(path: relativePath)
        }

        let processedBytes: [UInt8]
        if isTruncated {
            let (trimmed, _) = Self.trimIncompleteTrailingUTF8(bytes: output)
            processedBytes = trimmed
        } else {
            processedBytes = output
        }

        guard let utf8String = String(bytes: processedBytes, encoding: .utf8) else {
            throw WorkspaceAccessError.binaryFileNotSupported(path: relativePath)
        }

        let includesPartialFinalLine = !utf8String.isEmpty
            && !utf8String.hasSuffix("\n")
            && !lineLimitReached
        let finalLineCount = completedSelectedLines + (includesPartialFinalLine ? 1 : 0)
        if endLine != nil && reachedRequestedEnd {
            isTruncated = false
        }

        return WorkspaceFileRead(
            relativePath: relativePath,
            content: utf8String,
            byteCount: utf8String.utf8.count,
            lineCount: finalLineCount,
            isTruncated: isTruncated
        )
    }
}
