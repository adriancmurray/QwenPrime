import Foundation
import Darwin
import Testing
@testable import QwenPrime

/// Test fixture helper managing isolated temporary workspaces with guaranteed cleanup.
struct WorkspaceTestFixture: Sendable {
    let rootURL: URL

    init() throws {
        let tempBase = FileManager.default.temporaryDirectory
        let uniqueDirName = "qwenprime-workspace-test-\(UUID().uuidString)"
        let tempDirURL = tempBase.appendingPathComponent(uniqueDirName, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true)
        self.rootURL = tempDirURL
    }

    /// Creates a UTF-8 text file at the given relative path within the fixture root.
    @discardableResult
    func createFile(at relativePath: String, content: String) throws -> URL {
        let targetURL = rootURL.appendingPathComponent(relativePath)
        let parentURL = targetURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        guard let data = content.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try data.write(to: targetURL, options: .atomic)
        return targetURL
    }

    /// Creates a binary (non-UTF8) file with raw bytes at the given relative path.
    @discardableResult
    func createDataFile(at relativePath: String, data: Data) throws -> URL {
        let targetURL = rootURL.appendingPathComponent(relativePath)
        let parentURL = targetURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        try data.write(to: targetURL, options: .atomic)
        return targetURL
    }

    /// Creates a directory hierarchy at the given relative path within the fixture root.
    @discardableResult
    func createDirectory(at relativePath: String) throws -> URL {
        let targetURL = rootURL.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        return targetURL
    }

    /// Creates a symbolic link at `relativePath` pointing to `destinationPath`.
    @discardableResult
    func createSymlink(at relativePath: String, pointingTo destinationPath: String) throws -> URL {
        let targetURL = rootURL.appendingPathComponent(relativePath)
        let parentURL = targetURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: targetURL.path, withDestinationPath: destinationPath)
        return targetURL
    }

    /// Creates a FIFO (named pipe) special file at the given relative path within the fixture root.
    @discardableResult
    func createFIFO(at relativePath: String) throws -> URL {
        let targetURL = rootURL.appendingPathComponent(relativePath)
        let parentURL = targetURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        if mkfifo(targetURL.path, S_IRUSR | S_IWUSR) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return targetURL
    }

    /// Cleans up the temporary directory and all contents.
    func tearDown() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    /// Scoped execution ensuring teardown even on thrown errors.
    static func withFixture(_ body: (WorkspaceTestFixture) async throws -> Void) async throws {
        let fixture = try WorkspaceTestFixture()
        do {
            try await body(fixture)
            fixture.tearDown()
        } catch {
            fixture.tearDown()
            throw error
        }
    }
}

