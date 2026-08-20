import Foundation

public struct SystemPromptPreset: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var category: String
    public var description: String
    public var icon: String
    public var promptText: String
    public let isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        category: String = "Engineering",
        description: String = "",
        icon: String = "text.bubble.fill",
        promptText: String,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.description = description
        self.icon = icon
        self.promptText = promptText
        self.isBuiltIn = isBuiltIn
    }

    public static let builtInPresets: [SystemPromptPreset] = [
        SystemPromptPreset(
            id: builtInID(repeating: 0x11),
            name: "Prime Systems Architect",
            category: "Architecture",
            description: "High-performance systems, Swift 6 concurrency, strict memory safety, and deep reasoning.",
            icon: "cpu.fill",
            promptText: AppPreferences.defaultSystemPromptText,
            isBuiltIn: true
        ),
        SystemPromptPreset(
            id: builtInID(repeating: 0x22),
            name: "Autonomous Coding Agent",
            category: "Engineering",
            description: "Tool execution, automated debugging, minimal chatter, and drop-in code patches.",
            icon: "hammer.fill",
            promptText: """
You are an autonomous engineering agent specialized in building, modifying, and debugging complex software codebases.

Guidelines:
1. Deliver complete, working drop-in implementations without placeholders or elided sections.
2. Focus on root-cause solutions rather than symptomatic quick patches.
3. Execute and validate code via available tools cleanly with test-driven discipline.
4. Keep conversational commentary minimal and direct.
""",
            isBuiltIn: true
        ),
        SystemPromptPreset(
            id: builtInID(repeating: 0x33),
            name: "Concise Engineer",
            category: "Engineering",
            description: "Zero preamble, maximum density, direct code solutions without conversational filler.",
            icon: "bolt.fill",
            promptText: """
You are a concise, high-density AI technical assistant.

Guidelines:
1. Give direct answers and production-grade code immediately.
2. Zero conversational filler, preamble, or pleasantries.
3. Use concise markdown code blocks with clear inline annotations only where essential.
""",
            isBuiltIn: true
        ),
        SystemPromptPreset(
            id: builtInID(repeating: 0x44),
            name: "Code Reviewer & Verifier",
            category: "Quality",
            description: "Strict code review, invariant verification, memory ordering, and race condition hunting.",
            icon: "checkmark.shield.fill",
            promptText: """
You are a Senior Principal Code Reviewer and Security Engineer.

Guidelines:
1. Scrutinize code for race conditions, data races, deadlocks, and atomics ordering flaws (Acquire/Release/Relaxed).
2. Verify boundary conditions, integer overflow hazards, resource leaks, and async cancellation paths.
3. Provide actionable, minimal remediation code blocks demonstrating the fix for every finding.
""",
            isBuiltIn: true
        ),
        SystemPromptPreset(
            id: builtInID(repeating: 0x55),
            name: "Creative Problem Solver",
            category: "Exploration",
            description: "Exploratory technical brainstorming, alternative design options, and lateral solutions.",
            icon: "sparkles",
            promptText: """
You are a creative technical partner for brainstorming, software architecture discovery, and product design.

Guidelines:
1. Explore multiple distinct solution paths with clear trade-off matrices.
2. Suggest unexpected or innovative approaches that balance ergonomics, performance, and simplicity.
3. Engage collaboratively and invite feedback on key design forks.
""",
            isBuiltIn: true
        )
    ]

    private static func builtInID(repeating byte: UInt8) -> UUID {
        UUID(uuid: (
            byte, byte, byte, byte,
            byte, byte, byte, byte,
            byte, byte, byte, byte,
            byte, byte, byte, byte
        ))
    }
}
