import Foundation
import Testing
@testable import QwenPrime

@Suite("Agent skill service")
struct AgentSkillServiceTests {
    @Test("Discovers standard user and workspace SKILL.md packages")
    func discoversUserAndWorkspaceSkills() throws {
        let fixture = try SkillFixture()
        try fixture.writeSkill(
            root: fixture.userSkills,
            folder: "swift-review",
            name: "swift-review",
            description: "Review Swift concurrency.",
            instructions: "Check actor isolation."
        )
        try fixture.writeSkill(
            root: fixture.workspaceSkills,
            folder: "repo-rules",
            name: "repo-rules",
            description: "Follow repository rules.",
            instructions: "Read the package manifest first."
        )

        let service = AgentSkillService(userSkillsDirectory: fixture.userSkills)
        let skills = service.discover(workspaceURL: fixture.workspace)

        #expect(skills.map(\.name) == ["repo-rules", "swift-review"])
        #expect(skills.first(where: { $0.name == "repo-rules" })?.source == .workspace)
        #expect(skills.first(where: { $0.name == "swift-review" })?.source == .user)
    }

    @Test("Discovery ignores symlinked and oversized skill files")
    func rejectsUnsafeSkillFiles() throws {
        let fixture = try SkillFixture()
        let outside = fixture.root.appendingPathComponent("outside.md")
        try Data("---\nname: linked\ndescription: linked\n---\nDo not load.\n".utf8).write(to: outside)
        let linkedFolder = fixture.userSkills.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createDirectory(at: linkedFolder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: linkedFolder.appendingPathComponent("SKILL.md"),
            withDestinationURL: outside
        )
        try fixture.writeSkill(
            root: fixture.userSkills,
            folder: "oversized",
            name: "oversized",
            description: "Too large.",
            instructions: String(repeating: "x", count: AgentSkillService.maximumSkillBytes + 1)
        )

        let skills = AgentSkillService(userSkillsDirectory: fixture.userSkills)
            .discover(workspaceURL: fixture.workspace)

        #expect(skills.isEmpty)
    }

    @Test("Only explicitly mentioned enabled skills are selected")
    func selectsExplicitEnabledSkills() {
        let swift = AgentSkill.fixture(name: "swift-review", instructions: "Check isolation.")
        let rust = AgentSkill.fixture(name: "rust-review", instructions: "Check ownership.")

        let selected = AgentSkillService.selectInvokedSkills(
            in: "Use $swift-review, then explain the result. Do not use rust-review.",
            from: [swift, rust],
            enabledSkillIDs: [swift.id]
        )

        #expect(selected.map(\.id) == [swift.id])
    }

    @Test("Rendered skill context includes only selected instructions")
    func rendersBoundedSelectedSkillContext() {
        let selected = AgentSkill.fixture(name: "swift-review", instructions: "Check actor isolation.")
        let unselected = AgentSkill.fixture(name: "rust-review", instructions: "Check ownership.")

        let context = AgentSkillService.renderPromptContext(for: [selected])

        #expect(context.contains("<qwen-prime-skill name=\"swift-review\">"))
        #expect(context.contains("Check actor isolation."))
        #expect(!context.contains(unselected.instructions))
        #expect(context.utf8.count <= AgentSkillService.maximumPromptBytes)
    }

    @Test("Prompt budget truncation preserves a closed skill boundary")
    func boundedContextKeepsClosingTag() {
        let selected = AgentSkill.fixture(
            name: "large-review",
            instructions: String(repeating: "review carefully ", count: 8_000)
        )

        let context = AgentSkillService.renderPromptContext(for: [selected])

        #expect(context.utf8.count <= AgentSkillService.maximumPromptBytes)
        #expect(context.contains("<qwen-prime-skill name=\"large-review\">"))
        #expect(context.contains("</qwen-prime-skill>"))
    }

    @Test("Caller can assign a smaller shared prompt budget")
    func respectsCallerPromptBudget() {
        let selected = AgentSkill.fixture(
            name: "large-review",
            instructions: String(repeating: "review carefully ", count: 8_000)
        )

        let context = AgentSkillService.renderPromptContext(
            for: [selected],
            maximumBytes: 16 * 1024
        )

        #expect(context.utf8.count <= 16 * 1024)
        #expect(context.contains("</qwen-prime-skill>"))
    }
}

private struct SkillFixture {
    let root: URL
    let workspace: URL
    let workspaceSkills: URL
    let userSkills: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwen-prime-skills-\(UUID().uuidString)", isDirectory: true)
        workspace = root.appendingPathComponent("workspace", isDirectory: true)
        workspaceSkills = workspace
            .appendingPathComponent(".qwenprime", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
        userSkills = root.appendingPathComponent("user-skills", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceSkills, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userSkills, withIntermediateDirectories: true)
    }

    func writeSkill(
        root: URL,
        folder: String,
        name: String,
        description: String,
        instructions: String
    ) throws {
        let directory = root.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let content = """
        ---
        name: \(name)
        description: \(description)
        ---
        \(instructions)
        """
        try Data(content.utf8).write(to: directory.appendingPathComponent("SKILL.md"))
    }
}

private extension AgentSkill {
    static func fixture(name: String, instructions: String) -> AgentSkill {
        AgentSkill(
            name: name,
            description: "Fixture skill.",
            instructions: instructions,
            source: .user,
            fileURL: URL(fileURLWithPath: "/tmp/\(name)/SKILL.md")
        )
    }
}
