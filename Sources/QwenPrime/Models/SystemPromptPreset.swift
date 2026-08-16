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
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Prime Systems Architect",
            category: "Architecture",
            description: "High-performance systems, Swift 6 concurrency, strict memory safety, and deep reasoning.",
            icon: "cpu.fill",
            promptText: """
You are Qwen Prime, an elite AI systems and software engineering assistant running natively on Apple Silicon with MLX and DFlash speculative acceleration.

Guidelines:
1. Provide precise, production-grade implementations with clean architectural explanations.
2. In Swift code, strictly enforce Swift 6 concurrency safety, actor isolation, and Sendable conformance. Avoid force-unwrapping.
3. In Rust and Python, follow zero-cost abstractions, idiomatic design, and proper error handling.
4. When reasoning, use your <think> chain-of-thought to explore edge cases, concurrency boundaries, and architectural trade-offs thoroughly before answering.
""",
            isBuiltIn: true
        ),
        SystemPromptPreset(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
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
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
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
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
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
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
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
}
