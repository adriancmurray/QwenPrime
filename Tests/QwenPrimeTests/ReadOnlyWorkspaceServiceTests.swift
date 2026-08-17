import Foundation
import Testing
@testable import QwenPrime

@Suite("ReadOnlyWorkspaceService Core Operations Contract Tests")
struct ReadOnlyWorkspaceServiceTests {

    // MARK: - Contract 1 & 9: Root Initialization & Validation

    @Test("Service initializes with an explicit valid workspace root URL and default limits")
    func testInitializationCapturesRootAndLimits() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            #expect(service.rootURL.standardizedFileURL == fixture.rootURL.standardizedFileURL)
            #expect(service.limits == WorkspaceReadLimits.default)
        }
    }

    @Test("Service initializes with custom limits when provided")
    func testInitializationCapturesCustomLimits() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let customLimits = WorkspaceReadLimits(
                maxDirectoryEntries: 25,
                maxFileSizeBytes: 1024,
                maxFileLineCount: 50
            )
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL, limits: customLimits)
            #expect(service.limits == customLimits)
        }
    }

    @Test("Service initialization rejects non-positive maxDirectoryEntries limit")
    func testInitializationRejectsNonPositiveMaxDirectoryEntries() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let zeroLimits = WorkspaceReadLimits(
                maxDirectoryEntries: 0,
                maxFileSizeBytes: 1024,
                maxFileLineCount: 50
            )
            #expect(throws: WorkspaceAccessError.self) {
                _ = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL, limits: zeroLimits)
            }

            let negativeLimits = WorkspaceReadLimits(
                maxDirectoryEntries: -1,
                maxFileSizeBytes: 1024,
                maxFileLineCount: 50
            )
            #expect(throws: WorkspaceAccessError.self) {
                _ = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL, limits: negativeLimits)
            }
        }
    }

    @Test("Service initialization rejects non-positive maxFileSizeBytes limit")
    func testInitializationRejectsNonPositiveMaxFileSizeBytes() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let zeroLimits = WorkspaceReadLimits(
                maxDirectoryEntries: 10,
                maxFileSizeBytes: 0,
                maxFileLineCount: 50
            )
            #expect(throws: WorkspaceAccessError.self) {
                _ = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL, limits: zeroLimits)
            }

            let negativeLimits = WorkspaceReadLimits(
                maxDirectoryEntries: 10,
                maxFileSizeBytes: -64,
                maxFileLineCount: 50
            )
            #expect(throws: WorkspaceAccessError.self) {
                _ = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL, limits: negativeLimits)
            }
        }
    }

    @Test("Service initialization rejects non-positive maxFileLineCount limit")
    func testInitializationRejectsNonPositiveMaxFileLineCount() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let zeroLimits = WorkspaceReadLimits(
                maxDirectoryEntries: 10,
                maxFileSizeBytes: 1024,
                maxFileLineCount: 0
            )
            #expect(throws: WorkspaceAccessError.self) {
                _ = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL, limits: zeroLimits)
            }

            let negativeLimits = WorkspaceReadLimits(
                maxDirectoryEntries: 10,
                maxFileSizeBytes: 1024,
                maxFileLineCount: -10
            )
            #expect(throws: WorkspaceAccessError.self) {
                _ = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL, limits: negativeLimits)
            }
        }
    }

    @Test("Service initialization rejects non-existent root directory")
    func testInitializationRejectsMissingRoot() {
        let nonExistentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("non_existent_workspace_\(UUID().uuidString)")
        #expect(throws: WorkspaceAccessError.self) {
            _ = try ReadOnlyWorkspaceService(rootURL: nonExistentURL)
        }
    }

    @Test("Service initialization rejects regular file as root")
    func testInitializationRejectsFileAsRoot() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let fileURL = try fixture.createFile(at: "file_root.txt", content: "hello")
            #expect(throws: WorkspaceAccessError.self) {
                _ = try ReadOnlyWorkspaceService(rootURL: fileURL)
            }
        }
    }

    @Test("Service initialization rejects symlinked directory as root")
    func testInitializationRejectsSymlinkedRoot() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let realSubdir = try fixture.createDirectory(at: "real_root")
            let symlinkURL = fixture.rootURL.appendingPathComponent("symlink_root")
            try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: realSubdir)
            #expect(throws: WorkspaceAccessError.self) {
                _ = try ReadOnlyWorkspaceService(rootURL: symlinkURL)
            }
        }
    }

    // MARK: - Contract 2: Directory Listing (Deterministic Sorting, Non-Recursive, Truncation)

    @Test("listDirectory returns deterministically sorted entries distinguishing files and directories")
    func testListDirectoryDeterministicSortedEntries() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: "z_file.txt", content: "z")
            try fixture.createFile(at: "a_file.txt", content: "a")
            try fixture.createFile(at: "m_file.txt", content: "m")
            try fixture.createDirectory(at: "b_dir")

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let listing = try await service.listDirectory(relativePath: nil)

            #expect(listing.isTruncated == false)
            let names = listing.entries.map(\.name)
            #expect(names == ["a_file.txt", "b_dir", "m_file.txt", "z_file.txt"])

            let dirEntry = try #require(listing.entries.first { $0.name == "b_dir" })
            #expect(dirEntry.isDirectory == true)

            let fileEntry = try #require(listing.entries.first { $0.name == "a_file.txt" })
            #expect(fileEntry.isDirectory == false)
        }
    }

    @Test("listDirectory does not traverse automatically into nested subdirectories")
    func testListDirectoryNonRecursive() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createDirectory(at: "nested_folder")
            try fixture.createFile(at: "nested_folder/child_1.txt", content: "c1")
            try fixture.createFile(at: "nested_folder/child_2.txt", content: "c2")
            try fixture.createFile(at: "root_file.txt", content: "root")

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let rootListing = try await service.listDirectory(relativePath: "")

            let rootNames = rootListing.entries.map(\.name)
            #expect(rootNames == ["nested_folder", "root_file.txt"])
            #expect(!rootNames.contains("child_1.txt"))
            #expect(!rootNames.contains("child_2.txt"))

            let subListing = try await service.listDirectory(relativePath: "nested_folder")
            let subNames = subListing.entries.map(\.name)
            #expect(subNames == ["child_1.txt", "child_2.txt"])
        }
    }

    @Test("listDirectory caps output at default 200 entries and reports truncation")
    func testListDirectoryCapsAt200AndReportsTruncation() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createDirectory(at: "large_folder")
            for index in 1...220 {
                let padded = String(format: "%03d", index)
                try fixture.createFile(at: "large_folder/item_\(padded).txt", content: "data")
            }

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let listing = try await service.listDirectory(relativePath: "large_folder")

            #expect(listing.entries.count == 200)
            #expect(listing.isTruncated == true)
        }
    }

    @Test("listDirectory honors custom limit and reports truncation")
    func testListDirectoryHonorsCustomLimit() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createDirectory(at: "custom_folder")
            for index in 1...15 {
                let padded = String(format: "%02d", index)
                try fixture.createFile(at: "custom_folder/doc_\(padded).txt", content: "doc")
            }

            let customLimits = WorkspaceReadLimits(
                maxDirectoryEntries: 10,
                maxFileSizeBytes: 64 * 1024,
                maxFileLineCount: 500
            )
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL, limits: customLimits)
            let listing = try await service.listDirectory(relativePath: "custom_folder")

            #expect(listing.entries.count == 10)
            #expect(listing.isTruncated == true)
        }
    }

    // MARK: - Contract 3: File Reading (UTF-8, Byte Limit, Line Limit, Truncation)

    @Test("readFile reads UTF-8 text within limits and reports untruncated result")
    func testReadFileUTF8TextWithinLimits() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let text = "Hello from QwenPrime!\nLine 2 with UTF-8 symbols: 🚀 ⚡️\nLine 3"
            try fixture.createFile(at: "docs/readme.txt", content: text)

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let readResult = try await service.readFile(relativePath: "docs/readme.txt")

            #expect(readResult.relativePath == "docs/readme.txt")
            #expect(readResult.content == text)
            #expect(readResult.byteCount == text.utf8.count)
            #expect(readResult.lineCount == 3)
            #expect(readResult.isTruncated == false)
        }
    }

    @Test("readFile caps returned data at 500 lines and reports truncation")
    func testReadFileCapsAt500Lines() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let lines = (1...600).map { "Line \($0)" }
            let fullText = lines.joined(separator: "\n")
            try fixture.createFile(at: "lines.txt", content: fullText)

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let readResult = try await service.readFile(relativePath: "lines.txt")

            #expect(readResult.isTruncated == true)
            #expect(readResult.lineCount == 500)
            let resultLines = readResult.content.components(separatedBy: "\n")
            #expect(resultLines.count == 500)
            #expect(resultLines.first == "Line 1")
            #expect(resultLines.last == "Line 500")
        }
    }

    @Test("readFile caps returned data at 64 KiB and reports truncation")
    func testReadFileCapsAt64KiB() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            // 70 KiB string on a single line
            let oversizedText = String(repeating: "A", count: 70 * 1024)
            try fixture.createFile(at: "oversized.txt", content: oversizedText)

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let readResult = try await service.readFile(relativePath: "oversized.txt")

            #expect(readResult.isTruncated == true)
            #expect(readResult.byteCount == 64 * 1024)
            #expect(readResult.content.utf8.count == 64 * 1024)
        }
    }

    @Test("readFile honors custom byte and line limits")
    func testReadFileHonorsCustomLimits() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let lines = (1...50).map { "Entry \($0)" }
            let text = lines.joined(separator: "\n")
            try fixture.createFile(at: "custom_limit.txt", content: text)

            let customLimits = WorkspaceReadLimits(
                maxDirectoryEntries: 200,
                maxFileSizeBytes: 64 * 1024,
                maxFileLineCount: 20
            )
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL, limits: customLimits)
            let readResult = try await service.readFile(relativePath: "custom_limit.txt")

            #expect(readResult.isTruncated == true)
            #expect(readResult.lineCount == 20)
        }
    }

    @Test("readFile truncating inside a multibyte UTF-8 scalar preserves valid UTF-8 and reports actual byteCount")
    func testReadFileTruncationAtMultibyteUTF8Boundary() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            // "Hello-" is 6 ASCII bytes.
            // "🚀" (\u{1F680}) is 4 UTF-8 bytes (F0 9F 9A 80).
            // "World" is 5 ASCII bytes. Total = 15 bytes.
            let textWith4ByteScalar = "Hello-🚀World"
            try fixture.createFile(at: "multibyte4.txt", content: textWith4ByteScalar)

            // Byte limit of 8 lands in the middle of the 4-byte rocket emoji (bytes 6..<10).
            // Truncation must stop at byte 6 ("Hello-") rather than emitting corrupt UTF-8.
            let limitsInside4ByteScalar = WorkspaceReadLimits(
                maxDirectoryEntries: 200,
                maxFileSizeBytes: 8,
                maxFileLineCount: 500
            )
            let service4 = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL, limits: limitsInside4ByteScalar)
            let result4 = try await service4.readFile(relativePath: "multibyte4.txt")

            #expect(result4.isTruncated == true)
            #expect(result4.content == "Hello-")
            #expect(result4.byteCount == 6)
            #expect(result4.byteCount == result4.content.utf8.count)

            // "Euro-" is 5 ASCII bytes.
            // "€" (\u{20AC}) is 3 UTF-8 bytes (E2 82 AC).
            // "-Sign" is 5 ASCII bytes. Total = 13 bytes.
            let textWith3ByteScalar = "Euro-€-Sign"
            try fixture.createFile(at: "multibyte3.txt", content: textWith3ByteScalar)

            // Byte limit of 7 lands inside the 3-byte euro symbol (bytes 5..<8).
            // Truncation must stop at byte 5 ("Euro-").
            let limitsInside3ByteScalar = WorkspaceReadLimits(
                maxDirectoryEntries: 200,
                maxFileSizeBytes: 7,
                maxFileLineCount: 500
            )
            let service3 = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL, limits: limitsInside3ByteScalar)
            let result3 = try await service3.readFile(relativePath: "multibyte3.txt")

            #expect(result3.isTruncated == true)
            #expect(result3.content == "Euro-")
            #expect(result3.byteCount == 5)
            #expect(result3.byteCount == result3.content.utf8.count)
        }
    }

    // MARK: - Contract 10: Cancellation

    @Test("readFile deterministically honors Task cancellation")
    func testReadFileRespectsCancellation() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let text = String(repeating: "Deterministic cancellation test\n", count: 100)
            try fixture.createFile(at: "cancel_target.txt", content: text)

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)

            await #expect(throws: (any Error).self) {
                let task = Task {
                    // Trigger cooperative cancellation prior to read execution
                    withUnsafeCurrentTask { $0?.cancel() }
                    return try await service.readFile(relativePath: "cancel_target.txt")
                }
                _ = try await task.value
            }
        }
    }

    // MARK: - Contract: Directory Enumeration Operational Bound & Cancellation

    private func sourceFile(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }

    private func readSource(_ relativePath: String) throws -> String {
        try String(contentsOf: sourceFile(relativePath), encoding: .utf8)
    }

    @Test("BoundedWorkspaceEntrySelector pure behavioral test retains at most maxEntries in globally lexicographical order and tracks truncation")
    func testBoundedWorkspaceEntrySelectorBehavioral() {
        var selector = BoundedWorkspaceEntrySelector(maxEntries: 3)
        #expect(selector.totalCount == 0)
        #expect(selector.isTruncated == false)
        #expect(selector.selectedEntries.isEmpty)

        let names = ["z_last.txt", "m_mid.txt", "a_first.txt", "b_second.txt", "y_penultimate.txt", "aa_early.txt"]
        for name in names {
            selector.insert(WorkspaceEntry(
                name: name,
                relativePath: name,
                isDirectory: false,
                isPackageDirectory: false
            ))
            #expect(selector.selectedEntries.count <= 3)
        }

        #expect(selector.totalCount == 6)
        #expect(selector.isTruncated == true)
        #expect(selector.selectedEntries.count == 3)
        #expect(selector.selectedEntries.map(\.name) == ["a_first.txt", "aa_early.txt", "b_second.txt"])
    }

    @Test("ReadOnlyWorkspaceService.listDirectory uses bounded entry selector and checks Task cancellation inside readdir loop")
    func testListDirectoryUsesBoundedSelectorAndChecksCancellationInsideReaddir() throws {
        let serviceSource = try readSource("Sources/QwenPrime/Services/ReadOnlyWorkspaceService.swift")

        // 1. Must NOT accumulate entries into an unbounded array
        #expect(!serviceSource.contains("var rawEntries: [WorkspaceEntry] = []"))
        #expect(!serviceSource.contains("rawEntries.append("))

        // 2. Must use bounded entry selector
        #expect(
            serviceSource.contains("BoundedWorkspaceEntrySelector") ||
            serviceSource.contains("BoundedEntrySelector")
        )

        // 3. Must check Task cancellation inside the readdir loop
        guard let listDirRange = serviceSource.range(of: "func listDirectory(") else {
            Issue.record("Could not find listDirectory in ReadOnlyWorkspaceService.swift")
            return
        }
        guard let readFileRange = serviceSource.range(of: "func readFile(") else {
            Issue.record("Could not find readFile in ReadOnlyWorkspaceService.swift")
            return
        }
        let listDirBody = String(serviceSource[listDirRange.upperBound..<readFileRange.lowerBound])

        guard let readdirRange = listDirBody.range(of: "while let entryPtr = readdir") else {
            Issue.record("Could not find readdir loop in ReadOnlyWorkspaceService.swift")
            return
        }
        let readdirLoopBody = String(listDirBody[readdirRange.upperBound...])
        #expect(readdirLoopBody.contains("Task.checkCancellation()"))
    }
}

