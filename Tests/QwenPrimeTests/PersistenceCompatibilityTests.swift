import Testing
import Foundation
@testable import QwenPrime

@Suite("Persistence Compatibility Tests")
struct PersistenceCompatibilityTests {

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Persistence")
            .appendingPathComponent(name)
    }

    @Test("Shipped v1.1.0 conversation fixture decodes with expected values")
    func testV110ConversationFixtureDecoding() throws {
        let url = fixtureURL("v1_1_0_conversation.json")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let conversation = try decoder.decode(Conversation.self, from: data)

        #expect(conversation.id == UUID(uuidString: "A1B2C3D4-E5F6-4A1B-8C2D-3E4F5A6B7C8D"))
        #expect(conversation.title == "Actor Reentrancy in Swift")
        #expect(conversation.modelId == "qwen3.8-27b")
        #expect(conversation.temperature == 0.1)
        #expect(conversation.isThinkingEnabled == true)
        #expect(conversation.projectPath == "/Users/example/Projects/SampleApp")
        #expect(conversation.systemPrompt == "You are Qwen Prime, a helpful coding assistant.")
        #expect(conversation.messages.count == 2)

        let userMessage = conversation.messages[0]
        #expect(userMessage.id == UUID(uuidString: "B1B2C3D4-E5F6-4A1B-8C2D-3E4F5A6B7C8D"))
        #expect(userMessage.role == .user)
        #expect(userMessage.content == "How do I implement actor reentrancy prevention in Swift?")
        #expect(userMessage.thinkingContent == nil)
        #expect(!userMessage.isThinkingExpanded)
        #expect(!userMessage.isStreaming)
        #expect(userMessage.toolExecutions.isEmpty)
        #expect(userMessage.stats == nil)

        let assistantMessage = conversation.messages[1]
        #expect(assistantMessage.id == UUID(uuidString: "C1B2C3D4-E5F6-4A1B-8C2D-3E4F5A6B7C8D"))
        #expect(assistantMessage.role == .assistant)
        #expect(assistantMessage.content.contains("actor reentrancy safely in Swift"))
        #expect(assistantMessage.thinkingContent == "The user is asking about actor reentrancy in Swift concurrency. Explain post-await state validation.")
        #expect(!assistantMessage.isThinkingExpanded)
        #expect(!assistantMessage.isStreaming)
        #expect(assistantMessage.toolExecutions.isEmpty)
        #expect(assistantMessage.stats?.promptTokens == 28)
        #expect(assistantMessage.stats?.completionTokens == 32)
        #expect(assistantMessage.stats?.tokensPerSecond == 26.6)
        #expect(assistantMessage.stats?.latencySeconds == 1.2)
        #expect(assistantMessage.stats?.timeToFirstTokenSeconds == 0.15)
        #expect(assistantMessage.stats?.speculativeAcceptanceRate == 0.6)
        #expect(assistantMessage.stats?.acceptedDraftTokens == 6)
        #expect(assistantMessage.stats?.speculativeCycles == 10)
        #expect(assistantMessage.stats?.prefillSeconds == 0.15)
        #expect(assistantMessage.stats?.prefillTokensPerSecond == 186.6)
        #expect(assistantMessage.stats?.prefillTokensComputed == 28)
        #expect(assistantMessage.stats?.prefillTokensRestored == 0)
        #expect(assistantMessage.stats?.prefixCacheHitTokens == 0)
        #expect(assistantMessage.stats?.reasoningTokens == 10)
        #expect(assistantMessage.stats?.reasoningSeconds == 0.4)
        #expect(assistantMessage.stats?.isThroughputEstimated == false)
    }

    @Test("Workspace agent preview conversation fixture decodes cleanly with v1.1.0 domain types")
    func testWorkspaceAgentPreviewConversationFixtureDecoding() throws {
        let url = fixtureURL("future_agent_conversation.json")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let conversation = try decoder.decode(Conversation.self, from: data)

        #expect(conversation.id == UUID(uuidString: "D1B2C3D4-E5F6-4A1B-8C2D-3E4F5A6B7C8D"))
        #expect(conversation.title == "Inspect Package.swift")
        #expect(conversation.modelId == "qwen3.8-27b")
        #expect(conversation.temperature == 0.1)
        #expect(conversation.isThinkingEnabled == true)
        #expect(conversation.projectPath == "/Users/example/Projects/SampleApp")
        #expect(conversation.systemPrompt == "You are Qwen Prime, a helpful coding assistant equipped with workspace preview tools.")
        #expect(conversation.messages.count == 2)

        let userMessage = conversation.messages[0]
        #expect(userMessage.id == UUID(uuidString: "E1B2C3D4-E5F6-4A1B-8C2D-3E4F5A6B7C8D"))
        #expect(userMessage.role == .user)
        #expect(userMessage.content == "Inspect Package.swift in the workspace.")
        #expect(userMessage.toolExecutions.isEmpty)

        let assistantMessage = conversation.messages[1]
        #expect(assistantMessage.id == UUID(uuidString: "F1B2C3D4-E5F6-4A1B-8C2D-3E4F5A6B7C8D"))
        #expect(assistantMessage.role == .assistant)
        #expect(assistantMessage.content.contains("I have inspected Package.swift"))
        #expect(assistantMessage.thinkingContent == "I will inspect Package.swift using the workspace file reading tool.")
        #expect(assistantMessage.isThinkingExpanded == true)
        #expect(!assistantMessage.isStreaming)
        #expect(assistantMessage.stats?.promptTokens == 64)
        #expect(assistantMessage.stats?.completionTokens == 24)
        #expect(assistantMessage.stats?.tokensPerSecond == 30.0)
        #expect(assistantMessage.stats?.prefixCacheHitTokens == 32)
        #expect(assistantMessage.stats?.prefillTokensRestored == 32)
        #expect(assistantMessage.toolExecutions.count == 1)

        let tool = assistantMessage.toolExecutions[0]
        #expect(tool.id == "TOOL-EXEC-001")
        #expect(tool.toolName == "workspace_read_file")
        #expect(tool.input == "{\"path\":\"Package.swift\"}")
        #expect(tool.output?.contains("SampleApp") == true)
        #expect(tool.isRunning == false)
        #expect(tool.isSuccess == true)
    }

    @Test("ToolExecution input, output, and success survive serialization roundtrip")
    func testToolExecutionSerializationRoundtrip() throws {
        let successfulTool = ToolExecution(
            id: "tool-exec-success",
            toolName: "workspace_read_file",
            input: "{\"path\":\"Package.swift\"}",
            output: "// swift-tools-version: 6.0\nimport PackageDescription",
            isRunning: false,
            isSuccess: true
        )
        let failedTool = ToolExecution(
            id: "tool-exec-failure",
            toolName: "workspace_read_file",
            input: "{\"path\":\"Missing.swift\"}",
            output: "File not found: Missing.swift",
            isRunning: false,
            isSuccess: false
        )

        let assistantMessage = ChatMessage(
            role: .assistant,
            content: "Workspace inspection completed.",
            toolExecutions: [successfulTool, failedTool]
        )

        let conversation = Conversation(
            title: "Tool Execution Roundtrip",
            messages: [assistantMessage]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(conversation)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedConversation = try decoder.decode(Conversation.self, from: data)

        #expect(decodedConversation.messages.count == 1)
        let decodedTools = decodedConversation.messages[0].toolExecutions
        #expect(decodedTools.count == 2)

        #expect(decodedTools[0].id == successfulTool.id)
        #expect(decodedTools[0].toolName == successfulTool.toolName)
        #expect(decodedTools[0].input == successfulTool.input)
        #expect(decodedTools[0].output == successfulTool.output)
        #expect(decodedTools[0].isRunning == false)
        #expect(decodedTools[0].isSuccess == true)

        #expect(decodedTools[1].id == failedTool.id)
        #expect(decodedTools[1].toolName == failedTool.toolName)
        #expect(decodedTools[1].input == failedTool.input)
        #expect(decodedTools[1].output == failedTool.output)
        #expect(decodedTools[1].isRunning == false)
        #expect(decodedTools[1].isSuccess == false)
    }

    @Test("Persisted conversation fixtures contain no running tool executions")
    func testPersistedFixturesContainNoRunningToolExecutions() throws {
        let fixtureNames = [
            "v1_1_0_conversation.json",
            "future_agent_conversation.json"
        ]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for name in fixtureNames {
            let url = fixtureURL(name)
            let data = try Data(contentsOf: url)
            let conversation = try decoder.decode(Conversation.self, from: data)

            let allTools = conversation.messages.flatMap(\.toolExecutions)
            for tool in allTools {
                #expect(!tool.isRunning, "Persisted tool execution \(tool.id) in \(name) must not remain isRunning=true")
            }
        }
    }
}
