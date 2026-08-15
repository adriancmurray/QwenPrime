import Testing
import Foundation
@testable import QwenPrime

@Suite("QwenPrime Model & Storage Tests")
struct QwenPrimeTests {

    @Test("Conversation serialization and roundtrip")
    func testConversationSerialization() throws {
        let msg1 = ChatMessage(
            role: .user,
            content: "Hello Qwen!"
        )
        let msg2 = ChatMessage(
            role: .assistant,
            content: "Hello! How can I assist you with code today?",
            thinkingContent: "User greeted. Provide a friendly coding assistant greeting.",
            stats: GenerationStats(promptTokens: 12, completionTokens: 25, tokensPerSecond: 45.2, latencySeconds: 0.55)
        )

        var conv = Conversation(
            title: "Test Greeting",
            messages: [msg1, msg2],
            modelId: "qwen3.8-27b"
        )
        conv.touch()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(conv)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Conversation.self, from: data)

        #expect(decoded.id == conv.id)
        #expect(decoded.title == "Test Greeting")
        #expect(decoded.messages.count == 2)
        #expect(decoded.messages[1].thinkingContent == "User greeted. Provide a friendly coding assistant greeting.")
        #expect(decoded.messages[1].stats?.tokensPerSecond == 45.2)
    }

    @Test("StorageService save and delete lifecycle")
    func testStorageService() async throws {
        let storage = StorageService.shared
        let testId = UUID()
        let conv = Conversation(
            id: testId,
            title: "Unit Test Temp Conversation",
            messages: [ChatMessage(role: .user, content: "Ping")]
        )

        try await storage.saveConversation(conv)
        let all = try await storage.loadAllConversations()
        #expect(all.contains(where: { $0.id == testId }))

        try await storage.deleteConversation(id: testId)
        let afterDelete = try await storage.loadAllConversations()
        #expect(!afterDelete.contains(where: { $0.id == testId }))
    }

    @Test("GenerationStats total tokens calculation")
    func testGenerationStats() {
        let stats = GenerationStats(promptTokens: 100, completionTokens: 250, tokensPerSecond: 38.5, latencySeconds: 6.5)
        #expect(stats.totalTokens == 350)
        #expect(stats.tokensPerSecond == 38.5)
    }
}
