import Testing
import Foundation
@testable import QwenPrime

@Suite("Agent History Conversion Tests")
struct AgentHistoryConversionTests {

    @Test("ChatMessage history converts to ChatCompletionMessage transport preserving user, assistant reasoning, and reconstructing ToolExecution tool_calls and responses")
    func testChatMessageHistoryConversionToTransientTransport() {
        let msgId1 = UUID()
        let msgId2 = UUID()
        let msgId3 = UUID()

        let history: [ChatMessage] = [
            // 1. User message
            ChatMessage(
                id: msgId1,
                role: .user,
                content: "Find all models in the workspace"
            ),
            // 2. Assistant message with reasoning and tool execution
            ChatMessage(
                id: msgId2,
                role: .assistant,
                content: "",
                thinkingContent: "Let me check the Models directory first.",
                toolExecutions: [
                    ToolExecution(
                        id: "call_models_1",
                        toolName: "workspace_list_directory",
                        input: "{\"path\":\"Sources/QwenPrime/Models\"}",
                        output: "[\"ChatMessage.swift\",\"Conversation.swift\"]",
                        isRunning: false,
                        isSuccess: true
                    )
                ]
            ),
            // 3. Subsequent assistant explanation
            ChatMessage(
                id: msgId3,
                role: .assistant,
                content: "Found ChatMessage.swift and Conversation.swift.",
                thinkingContent: "Now summarizing results for user."
            )
        ]

        let transportMessages = NativeAgentRuntime.buildInitialTranscript(from: history)

        // Expected transcript:
        // 1. User: "Find all models in the workspace"
        // 2. Assistant: reasoning="Let me check...", tool_calls=[call_models_1]
        // 3. Tool: tool_call_id="call_models_1", content="[\"ChatMessage.swift\",\"Conversation.swift\"]"
        // 4. Assistant: reasoning="Now summarizing...", content="Found ChatMessage.swift..."

        #expect(transportMessages.count == 4)

        if transportMessages.count >= 4 {
            // Message 1: User
            #expect(transportMessages[0].role == .user)
            #expect(transportMessages[0].content == "Find all models in the workspace")
            #expect(transportMessages[0].toolCalls == nil)
            #expect(transportMessages[0].toolCallId == nil)

            // Message 2: Assistant with reconstructed tool_calls and reasoning
            #expect(transportMessages[1].role == .assistant)
            #expect(transportMessages[1].reasoningContent == "Let me check the Models directory first.")
            #expect(transportMessages[1].toolCalls?.count == 1)
            if let toolCall = transportMessages[1].toolCalls?.first {
                #expect(toolCall.id == "call_models_1")
                #expect(toolCall.type == "function")
                #expect(toolCall.function.name == "workspace_list_directory")
                #expect(toolCall.function.arguments == "{\"path\":\"Sources/QwenPrime/Models\"}")
            }

            // Message 3: Tool response with matching tool_call_id
            #expect(transportMessages[2].role == .tool)
            #expect(transportMessages[2].toolCallId == "call_models_1")
            #expect(transportMessages[2].content == "[\"ChatMessage.swift\",\"Conversation.swift\"]")

            // Message 4: Assistant follow-up
            #expect(transportMessages[3].role == .assistant)
            #expect(transportMessages[3].content == "Found ChatMessage.swift and Conversation.swift.")
            #expect(transportMessages[3].reasoningContent == "Now summarizing results for user.")
        }
    }

    @Test("ChatMessage history conversion with system prompt in configuration handles system message cleanly")
    func testChatMessageHistoryConversionWithSystemRole() {
        let history: [ChatMessage] = [
            ChatMessage(role: .system, content: "System instructions"),
            ChatMessage(role: .user, content: "User prompt")
        ]

        let transportMessages = NativeAgentRuntime.buildInitialTranscript(from: history)
        #expect(transportMessages.count == 2)
        if transportMessages.count >= 2 {
            #expect(transportMessages[0].role == .system)
            #expect(transportMessages[0].content == "System instructions")
            #expect(transportMessages[1].role == .user)
            #expect(transportMessages[1].content == "User prompt")
        }
    }

    @Test("buildInitialTranscript skips ToolExecution entries that are isRunning or have isSuccess == nil")
    func testBuildInitialTranscriptSkipsRunningAndUnfinishedToolExecutions() {
        let history: [ChatMessage] = [
            ChatMessage(role: .user, content: "Inspect tools"),
            ChatMessage(
                role: .assistant,
                content: "",
                toolExecutions: [
                    // 1. Completed successfully -> should be included
                    ToolExecution(
                        id: "call_valid_1",
                        toolName: "workspace_read_file",
                        input: "{\"path\":\"valid.txt\"}",
                        output: "valid content",
                        isRunning: false,
                        isSuccess: true
                    ),
                    // 2. Currently running -> should be skipped
                    ToolExecution(
                        id: "call_running_2",
                        toolName: "workspace_read_file",
                        input: "{\"path\":\"running.txt\"}",
                        output: nil,
                        isRunning: true,
                        isSuccess: nil
                    ),
                    // 3. Stopped / isRunning is false but isSuccess is nil (unfinished / interrupted) -> should be skipped
                    ToolExecution(
                        id: "call_unfinished_3",
                        toolName: "workspace_read_file",
                        input: "{\"path\":\"unfinished.txt\"}",
                        output: "partial data",
                        isRunning: false,
                        isSuccess: nil
                    ),
                    // 4. Completed with failure (isSuccess == false) -> should be included
                    ToolExecution(
                        id: "call_failed_4",
                        toolName: "workspace_read_file",
                        input: "{\"path\":\"failed.txt\"}",
                        output: "File not found",
                        isRunning: false,
                        isSuccess: false
                    )
                ]
            )
        ]

        let transcript = NativeAgentRuntime.buildInitialTranscript(from: history)

        // Expected transcript:
        // Message 0: user "Inspect tools"
        // Message 1: assistant with toolCalls for [call_valid_1, call_failed_4] ONLY
        // Message 2: role=tool for call_valid_1
        // Message 3: role=tool for call_failed_4
        #expect(transcript.count == 4)

        if transcript.count >= 2 {
            let assistantMsg = transcript[1]
            #expect(assistantMsg.role == .assistant)
            let toolCalls = assistantMsg.toolCalls ?? []
            #expect(toolCalls.count == 2)
            #expect(toolCalls.map(\.id) == ["call_valid_1", "call_failed_4"])
        }

        let toolMessages = transcript.filter { $0.role == .tool }
        #expect(toolMessages.count == 2)
        #expect(toolMessages.compactMap(\.toolCallId) == ["call_valid_1", "call_failed_4"])
    }

    @Test("buildInitialTranscript never creates an invalid role=tool message from an unpaired persisted ChatMessage.role.tool that lacks tool_call_id")
    func testBuildInitialTranscriptOmitsUnpairedToolMessageLackingToolCallId() {
        let history: [ChatMessage] = [
            ChatMessage(role: .user, content: "Initial query"),
            // Unpaired persisted ChatMessage with role .tool lacking any tool_call_id
            ChatMessage(role: .tool, content: "Unpaired orphan tool output"),
            ChatMessage(role: .assistant, content: "Final answer")
        ]

        let transcript = NativeAgentRuntime.buildInitialTranscript(from: history)

        // Must NOT create an invalid role=tool message with nil/missing toolCallId
        let invalidToolMessages = transcript.filter { $0.role == .tool && ($0.toolCallId == nil || $0.toolCallId?.isEmpty == true) }
        #expect(invalidToolMessages.isEmpty)

        // Transcript should only contain the valid user and assistant messages
        #expect(transcript.count == 2)
        if transcript.count == 2 {
            #expect(transcript[0].role == .user)
            #expect(transcript[0].content == "Initial query")
            #expect(transcript[1].role == .assistant)
            #expect(transcript[1].content == "Final answer")
        }
    }
}
