import Foundation
import Testing
@testable import QwenPrime

@Suite("Workspace instruction service")
struct WorkspaceInstructionServiceTests {
    @Test("Loads only a regular UTF-8 root AGENTS.md")
    func loadsRootInstructions() throws {
        let fixture = try WorkspaceInstructionFixture()
        defer { fixture.tearDown() }
        try fixture.writeRootInstructions("ROOT-INSTRUCTIONS")
        try fixture.writeNestedInstructions("NESTED-INSTRUCTIONS")

        let document = WorkspaceInstructionService().load(workspaceURL: fixture.workspaceURL)

        #expect(document?.fileURL.lastPathComponent == "AGENTS.md")
        #expect(document?.content == "ROOT-INSTRUCTIONS")
        #expect(document?.content.contains("NESTED-INSTRUCTIONS") == false)
    }

    @Test("Rejects symlinked, oversized, binary, and invalid UTF-8 instruction files")
    func rejectsUnsafeInstructions() throws {
        let fixture = try WorkspaceInstructionFixture()
        defer { fixture.tearDown() }
        let service = WorkspaceInstructionService()

        let outside = fixture.rootURL.appendingPathComponent("outside.md")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: fixture.workspaceURL.appendingPathComponent("AGENTS.md"),
            withDestinationURL: outside
        )
        #expect(service.load(workspaceURL: fixture.workspaceURL) == nil)

        try FileManager.default.removeItem(at: fixture.workspaceURL.appendingPathComponent("AGENTS.md"))
        try Data(repeating: 0x61, count: WorkspaceInstructionService.maximumInstructionBytes + 1)
            .write(to: fixture.workspaceURL.appendingPathComponent("AGENTS.md"))
        #expect(service.load(workspaceURL: fixture.workspaceURL) == nil)

        try Data([0x61, 0x00, 0x62]).write(to: fixture.workspaceURL.appendingPathComponent("AGENTS.md"))
        #expect(service.load(workspaceURL: fixture.workspaceURL) == nil)

        try Data([0xFF, 0xFE]).write(to: fixture.workspaceURL.appendingPathComponent("AGENTS.md"))
        #expect(service.load(workspaceURL: fixture.workspaceURL) == nil)
    }

    @Test("Rendered context is bounded and preserves a closed instruction boundary")
    func rendersBoundedContext() {
        let document = WorkspaceInstructionDocument(
            content: String(repeating: "follow carefully ", count: 8_000),
            fileURL: URL(fileURLWithPath: "/tmp/AGENTS.md")
        )

        let context = WorkspaceInstructionService.renderPromptContext(document)

        #expect(context.utf8.count <= WorkspaceInstructionService.maximumPromptBytes)
        #expect(context.contains("<qwen-prime-workspace-instructions file=\"AGENTS.md\">"))
        #expect(context.contains("</qwen-prime-workspace-instructions>"))
        #expect(context.contains("do not grant additional authority"))
    }

    @Test("Caller can assign a smaller shared prompt budget")
    func respectsCallerPromptBudget() {
        let document = WorkspaceInstructionDocument(
            content: String(repeating: "follow carefully ", count: 8_000),
            fileURL: URL(fileURLWithPath: "/tmp/AGENTS.md")
        )

        let context = WorkspaceInstructionService.renderPromptContext(
            document,
            maximumBytes: 16 * 1024
        )

        #expect(context.utf8.count <= 16 * 1024)
        #expect(context.contains("</qwen-prime-workspace-instructions>"))
    }
}

private struct WorkspaceInstructionFixture {
    let rootURL: URL
    let workspaceURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwenprime-instructions-\(UUID().uuidString)", isDirectory: true)
        workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    }

    func writeRootInstructions(_ content: String) throws {
        try Data(content.utf8).write(to: workspaceURL.appendingPathComponent("AGENTS.md"))
    }

    func writeNestedInstructions(_ content: String) throws {
        let nested = workspaceURL.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(content.utf8).write(to: nested.appendingPathComponent("AGENTS.md"))
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
