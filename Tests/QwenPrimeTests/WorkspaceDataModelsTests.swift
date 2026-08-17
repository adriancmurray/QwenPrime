import Foundation
import Testing
@testable import QwenPrime

@Suite("Workspace Data Models and Limits Contract Tests")
struct WorkspaceDataModelsTests {

    @Test("WorkspaceReadLimits exposes correct default thresholds and supports custom configurations")
    func testWorkspaceReadLimitsDefaultsAndCustomValues() {
        let defaultLimits = WorkspaceReadLimits.default
        #expect(defaultLimits.maxDirectoryEntries == 200)
        #expect(defaultLimits.maxFileSizeBytes == 64 * 1024)
        #expect(defaultLimits.maxFileLineCount == 500)

        let customLimits = WorkspaceReadLimits(
            maxDirectoryEntries: 50,
            maxFileSizeBytes: 16 * 1024,
            maxFileLineCount: 100
        )
        #expect(customLimits.maxDirectoryEntries == 50)
        #expect(customLimits.maxFileSizeBytes == 16384)
        #expect(customLimits.maxFileLineCount == 100)
        #expect(customLimits != defaultLimits)
    }

    @Test("WorkspaceEntry models file and directory metadata with value equality and sorting")
    func testWorkspaceEntryPropertiesAndSorting() {
        let fileEntry = WorkspaceEntry(
            name: "main.swift",
            relativePath: "Sources/main.swift",
            isDirectory: false,
            isPackageDirectory: false,
            sizeBytes: 1024
        )
        let dirEntry = WorkspaceEntry(
            name: "Sources",
            relativePath: "Sources",
            isDirectory: true,
            isPackageDirectory: false,
            sizeBytes: nil
        )
        let packageEntry = WorkspaceEntry(
            name: "App.bundle",
            relativePath: "Resources/App.bundle",
            isDirectory: true,
            isPackageDirectory: true,
            sizeBytes: nil
        )

        #expect(fileEntry.name == "main.swift")
        #expect(fileEntry.relativePath == "Sources/main.swift")
        #expect(fileEntry.isDirectory == false)
        #expect(fileEntry.isPackageDirectory == false)
        #expect(fileEntry.sizeBytes == 1024)

        #expect(dirEntry.isDirectory == true)
        #expect(packageEntry.isPackageDirectory == true)

        let entries = [fileEntry, dirEntry, packageEntry].sorted { $0.relativePath < $1.relativePath }
        #expect(entries.map(\.relativePath) == ["Resources/App.bundle", "Sources", "Sources/main.swift"])
    }

    @Test("WorkspaceDirectoryListing models directory contents and truncation flag")
    func testWorkspaceDirectoryListingProperties() {
        let entry1 = WorkspaceEntry(
            name: "a.txt",
            relativePath: "a.txt",
            isDirectory: false,
            isPackageDirectory: false,
            sizeBytes: 10
        )
        let entry2 = WorkspaceEntry(
            name: "b.txt",
            relativePath: "b.txt",
            isDirectory: false,
            isPackageDirectory: false,
            sizeBytes: 20
        )

        let listing = WorkspaceDirectoryListing(
            relativePath: "",
            entries: [entry1, entry2],
            isTruncated: false
        )

        #expect(listing.relativePath == "")
        #expect(listing.entries.count == 2)
        #expect(listing.isTruncated == false)
    }

    @Test("WorkspaceFileRead models UTF-8 content, counts, and truncation status")
    func testWorkspaceFileReadProperties() {
        let content = "line 1\nline 2\nline 3"
        let fileRead = WorkspaceFileRead(
            relativePath: "README.md",
            content: content,
            byteCount: content.utf8.count,
            lineCount: 3,
            isTruncated: false
        )

        #expect(fileRead.relativePath == "README.md")
        #expect(fileRead.content == content)
        #expect(fileRead.byteCount == content.utf8.count)
        #expect(fileRead.lineCount == 3)
        #expect(fileRead.isTruncated == false)
    }

    @Test("WorkspaceAccessError provides typed equatable errors for security and access failures")
    func testWorkspaceAccessErrorEquatability() {
        let rootNotFound = WorkspaceAccessError.workspaceRootNotFound(path: "/missing/root")
        let rootNotDir = WorkspaceAccessError.workspaceRootNotDirectory(path: "/root/file.txt")
        let rootSymlink = WorkspaceAccessError.workspaceRootIsSymlink(path: "/root/symlink")
        let pathTraversal = WorkspaceAccessError.pathTraversal(path: "../escape")
        let symlinkDenied = WorkspaceAccessError.symlinkNotAllowed(path: "link.txt")
        let binaryDenied = WorkspaceAccessError.binaryFileNotSupported(path: "image.png")
        let isDirError = WorkspaceAccessError.isDirectory(path: "Sources")
        let opaqueRestricted = WorkspaceAccessError.opaquePackageRestricted(path: "App.app")
        let secretRestricted = WorkspaceAccessError.secretPathRestricted(path: ".env")

        #expect(rootNotFound == WorkspaceAccessError.workspaceRootNotFound(path: "/missing/root"))
        #expect(rootNotFound != rootNotDir)
        #expect(pathTraversal == WorkspaceAccessError.pathTraversal(path: "../escape"))
        #expect(symlinkDenied == WorkspaceAccessError.symlinkNotAllowed(path: "link.txt"))
        #expect(binaryDenied == WorkspaceAccessError.binaryFileNotSupported(path: "image.png"))
        #expect(isDirError == WorkspaceAccessError.isDirectory(path: "Sources"))
        #expect(opaqueRestricted == WorkspaceAccessError.opaquePackageRestricted(path: "App.app"))
        #expect(secretRestricted == WorkspaceAccessError.secretPathRestricted(path: ".env"))
        #expect(rootSymlink == WorkspaceAccessError.workspaceRootIsSymlink(path: "/root/symlink"))
    }
}
