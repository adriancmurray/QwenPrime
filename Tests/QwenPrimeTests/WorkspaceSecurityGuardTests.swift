import Foundation
import Testing
@testable import QwenPrime

@Suite("Workspace Security and Path Guard Contract Tests")
struct WorkspaceSecurityGuardTests {

    // MARK: - Contract 4: Absolute Paths, Empty Paths, Dot, and Traversal Rejection

    @Test("readFile and listDirectory reject absolute paths")
    func testRejectAbsolutePaths() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)

            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "/etc/passwd")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "/var/log/system.log")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.listDirectory(relativePath: "/usr/local")
            }
        }
    }

    @Test("readFile rejects empty path and whitespace-only path")
    func testRejectEmptyPath() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)

            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "   ")
            }
        }
    }

    @Test("readFile rejects dot where a file is required")
    func testRejectDotAsFilePath() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)

            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: ".")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "./")
            }
        }
    }

    @Test("readFile and listDirectory reject all parent directory traversal attempts")
    func testRejectParentDirectoryTraversal() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createDirectory(at: "sub")
            try fixture.createFile(at: "sub/valid.txt", content: "valid")

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)

            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "../escape.txt")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "sub/../../escape.txt")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "sub/../..")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.listDirectory(relativePath: "..")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.listDirectory(relativePath: "sub/../..")
            }
        }
    }

    @Test("readFile and listDirectory reject any '..' component even if lexical normalization stays within workspace")
    func testRejectDotDotComponentEvenIfLexicallyInsideWorkspace() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: "README.md", content: "hello")
            try fixture.createDirectory(at: "Sources")
            try fixture.createFile(at: "Sources/main.swift", content: "print(1)")

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)

            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "Sources/../README.md")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "Sources/../Sources/main.swift")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.listDirectory(relativePath: "Sources/..")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.listDirectory(relativePath: "Sources/../Sources")
            }
        }
    }

    @Test("readFile and listDirectory reject paths containing a NUL scalar before filesystem/POSIX bridging")
    func testRejectPathsContainingNULScalar() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: "valid.txt", content: "valid")
            try fixture.createDirectory(at: "sub")

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)

            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "valid.txt\0/etc/passwd")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "valid.txt\u{0000}.secret")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "\0secret.txt")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.listDirectory(relativePath: "sub\0/something")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.listDirectory(relativePath: "\u{0000}")
            }
        }
    }

    // MARK: - Contract 5: Symbolic Link Rejection

    @Test("readFile rejects symlink pointing outside workspace")
    func testRejectSymlinkPointingOutsideWorkspace() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            try fixture.createSymlink(at: "outside_link.txt", pointingTo: "/tmp/outside_secret.txt")

            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "outside_link.txt")
            }
        }
    }

    @Test("readFile rejects symlink pointing inside workspace")
    func testRejectSymlinkPointingInsideWorkspace() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: "real_target.txt", content: "hello")
            try fixture.createSymlink(at: "inside_link.txt", pointingTo: "real_target.txt")

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)

            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "inside_link.txt")
            }
        }
    }

    @Test("readFile and listDirectory reject intermediate symlink path components")
    func testRejectIntermediateSymlinkPathComponent() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let realDir = try fixture.createDirectory(at: "real_dir")
            try fixture.createFile(at: "real_dir/file.txt", content: "nested")
            try fixture.createSymlink(at: "sym_dir", pointingTo: realDir.path)

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)

            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "sym_dir/file.txt")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.listDirectory(relativePath: "sym_dir")
            }
        }
    }

    // MARK: - Contract 6: Binary Content & Directory-as-File

    @Test("readFile rejects binary and non-UTF8 encoded files")
    func testRejectBinaryContent() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            // Invalid UTF-8 byte sequence
            let invalidUTF8 = Data([0xFF, 0xFE, 0xFD, 0x00, 0xAA, 0xBB])
            try fixture.createDataFile(at: "image.bin", data: invalidUTF8)

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)

            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "image.bin")
            }
        }
    }

    @Test("readFile rejects reading a directory path as a file")
    func testRejectReadingDirectoryAsFile() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createDirectory(at: "my_folder")

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)

            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "my_folder")
            }
        }
    }

    @Test("readFile rejects file whose bytes are otherwise valid UTF-8 but contain NUL bytes")
    func testRejectValidUTF8ContainingNULBytes() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let validUTF8WithNUL = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x00, 0x57, 0x6F, 0x72, 0x6C, 0x64])
            try fixture.createDataFile(at: "embedded_nul.txt", data: validUTF8WithNUL)

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)

            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "embedded_nul.txt")
            }
        }
    }

    @Test("readFile rejects FIFO special file as not a regular file without attempting content I/O")
    func testRejectFIFOSpecialFileWithoutContentIO() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFIFO(at: "special.fifo")

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)

            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "special.fifo")
            }
        }
    }

    // MARK: - Contract 7: Compiled/Package Directories vs Xcode Projects

    @Test("Compiled packages (.app, .bundle, .framework) are opaque and cannot be descended into")
    func testOpaquePackageDirectoriesRestricted() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createDirectory(at: "MyApp.app/Contents")
            try fixture.createFile(at: "MyApp.app/Contents/Info.plist", content: "<plist/>")

            try fixture.createDirectory(at: "Plugin.bundle")
            try fixture.createFile(at: "Plugin.bundle/resource.dat", content: "data")

            try fixture.createDirectory(at: "MyKit.framework/Headers")
            try fixture.createFile(at: "MyKit.framework/Headers/MyKit.h", content: "// header")

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let rootListing = try await service.listDirectory(relativePath: "")

            // Packages should appear in parent listing with isPackageDirectory flag
            let appEntry = try #require(rootListing.entries.first { $0.name == "MyApp.app" })
            #expect(appEntry.isPackageDirectory == true)

            let bundleEntry = try #require(rootListing.entries.first { $0.name == "Plugin.bundle" })
            #expect(bundleEntry.isPackageDirectory == true)

            let frameworkEntry = try #require(rootListing.entries.first { $0.name == "MyKit.framework" })
            #expect(frameworkEntry.isPackageDirectory == true)

            // Descending into opaque packages must be rejected
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.listDirectory(relativePath: "MyApp.app")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "MyApp.app/Contents/Info.plist")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.listDirectory(relativePath: "Plugin.bundle")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "Plugin.bundle/resource.dat")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.listDirectory(relativePath: "MyKit.framework")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "MyKit.framework/Headers/MyKit.h")
            }
        }
    }

    @Test("Opaque package suffixes (.app, .bundle, .framework) are matched case-insensitively, including Example.APP")
    func testOpaquePackageDirectoriesCaseInsensitiveMatching() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createDirectory(at: "Example.APP/Contents")
            try fixture.createFile(at: "Example.APP/Contents/Info.plist", content: "<plist/>")

            try fixture.createDirectory(at: "Plugin.BUNDLE")
            try fixture.createFile(at: "Plugin.BUNDLE/data.bin", content: "data")

            try fixture.createDirectory(at: "MyKit.FRAMEWORK/Headers")
            try fixture.createFile(at: "MyKit.FRAMEWORK/Headers/header.h", content: "// header")

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let rootListing = try await service.listDirectory(relativePath: "")

            let appEntry = try #require(rootListing.entries.first { $0.name == "Example.APP" })
            #expect(appEntry.isPackageDirectory == true)

            let bundleEntry = try #require(rootListing.entries.first { $0.name == "Plugin.BUNDLE" })
            #expect(bundleEntry.isPackageDirectory == true)

            let frameworkEntry = try #require(rootListing.entries.first { $0.name == "MyKit.FRAMEWORK" })
            #expect(frameworkEntry.isPackageDirectory == true)

            // Access inside case-insensitive package directories must be rejected
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.listDirectory(relativePath: "Example.APP")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "Example.APP/Contents/Info.plist")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.listDirectory(relativePath: "Plugin.BUNDLE")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "Plugin.BUNDLE/data.bin")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.listDirectory(relativePath: "MyKit.FRAMEWORK")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "MyKit.FRAMEWORK/Headers/header.h")
            }
        }
    }

    @Test("Xcode projects and workspaces (.xcodeproj, .xcworkspace) allow directory listing and file reads")
    func testXcodeProjectsAndWorkspacesInspectable() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createDirectory(at: "App.xcodeproj")
            try fixture.createFile(at: "App.xcodeproj/project.pbxproj", content: "// PBX project content")

            try fixture.createDirectory(at: "App.xcworkspace")
            try fixture.createFile(at: "App.xcworkspace/contents.xcworkspacedata", content: "<Workspace version = \"1.0\">")

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)

            let projListing = try await service.listDirectory(relativePath: "App.xcodeproj")
            #expect(projListing.entries.contains { $0.name == "project.pbxproj" })

            let pbxFile = try await service.readFile(relativePath: "App.xcodeproj/project.pbxproj")
            #expect(pbxFile.content == "// PBX project content")

            let wsListing = try await service.listDirectory(relativePath: "App.xcworkspace")
            #expect(wsListing.entries.contains { $0.name == "contents.xcworkspacedata" })

            let wsFile = try await service.readFile(relativePath: "App.xcworkspace/contents.xcworkspacedata")
            #expect(wsFile.content == "<Workspace version = \"1.0\">")
        }
    }

    // MARK: - Contract 8: Secret-Bearing Paths vs Safe Dotfiles

    @Test("Secret-bearing paths (.git, .env, *.pem, *.key, id_rsa, id_ed25519) are denied")
    func testDenySecretBearingPaths() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createDirectory(at: ".git/hooks")
            try fixture.createFile(at: ".git/config", content: "[core]")
            try fixture.createFile(at: ".git/HEAD", content: "ref: refs/heads/main")
            try fixture.createFile(at: ".env", content: "SECRET_KEY=123")
            try fixture.createFile(at: ".env.local", content: "LOCAL_SECRET=abc")
            try fixture.createFile(at: ".env.production", content: "PROD_SECRET=xyz")
            try fixture.createFile(at: "server.pem", content: "-----BEGIN CERTIFICATE-----")
            try fixture.createFile(at: "private.key", content: "-----BEGIN PRIVATE KEY-----")
            try fixture.createFile(at: "id_rsa", content: "-----BEGIN RSA PRIVATE KEY-----")
            try fixture.createFile(at: "id_ed25519", content: "-----BEGIN OPENSSH PRIVATE KEY-----")

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)

            // .git internals denied
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: ".git/config")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.listDirectory(relativePath: ".git")
            }

            // .env denied
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: ".env")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: ".env.local")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: ".env.production")
            }

            // Key files denied
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "server.pem")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "private.key")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "id_rsa")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "id_ed25519")
            }
        }
    }

    @Test("Secret extensions and names are matched case-insensitively (.ENV, SECRET.PEM, PRIVATE.KEY, ID_RSA, ID_ED25519)")
    func testDenySecretBearingPathsCaseInsensitive() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: ".ENV", content: "SECRET=1")
            try fixture.createFile(at: ".ENV.LOCAL", content: "SECRET=2")
            try fixture.createFile(at: ".ENV.PRODUCTION", content: "SECRET=3")
            try fixture.createFile(at: "SECRET.PEM", content: "-----BEGIN CERTIFICATE-----")
            try fixture.createFile(at: "PRIVATE.KEY", content: "-----BEGIN PRIVATE KEY-----")
            try fixture.createFile(at: "ID_RSA", content: "-----BEGIN RSA PRIVATE KEY-----")
            try fixture.createFile(at: "ID_ED25519", content: "-----BEGIN OPENSSH PRIVATE KEY-----")
            try fixture.createDirectory(at: ".GIT/objects")
            try fixture.createFile(at: ".GIT/config", content: "[core]")

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)

            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: ".ENV")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: ".ENV.LOCAL")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: ".ENV.PRODUCTION")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "SECRET.PEM")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "PRIVATE.KEY")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "ID_RSA")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: "ID_ED25519")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.readFile(relativePath: ".GIT/config")
            }
            await #expect(throws: WorkspaceAccessError.self) {
                _ = try await service.listDirectory(relativePath: ".GIT")
            }
        }
    }

    @Test("Safe dotfiles and env template files (.env.example, .env.sample, .gitignore, etc.) remain readable")
    func testAllowSafeDotFilesAndEnvTemplates() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: ".env.example", content: "API_KEY=your_key_here")
            try fixture.createFile(at: ".env.sample", content: "SAMPLE_CONFIG=1")
            try fixture.createFile(at: ".env.template", content: "TEMPLATE=true")
            try fixture.createFile(at: ".gitignore", content: ".build/\n.DS_Store")
            try fixture.createFile(at: ".swiftlint.yml", content: "disabled_rules:\n  - trailing_whitespace")
            try fixture.createFile(at: ".editorconfig", content: "root = true")

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)

            let envExample = try await service.readFile(relativePath: ".env.example")
            #expect(envExample.content == "API_KEY=your_key_here")

            let envSample = try await service.readFile(relativePath: ".env.sample")
            #expect(envSample.content == "SAMPLE_CONFIG=1")

            let envTemplate = try await service.readFile(relativePath: ".env.template")
            #expect(envTemplate.content == "TEMPLATE=true")

            let gitignore = try await service.readFile(relativePath: ".gitignore")
            #expect(gitignore.content == ".build/\n.DS_Store")

            let swiftlint = try await service.readFile(relativePath: ".swiftlint.yml")
            #expect(swiftlint.content == "disabled_rules:\n  - trailing_whitespace")

            let editorconfig = try await service.readFile(relativePath: ".editorconfig")
            #expect(editorconfig.content == "root = true")
        }
    }
}

