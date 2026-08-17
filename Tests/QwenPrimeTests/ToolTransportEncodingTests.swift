import Testing
import Foundation
@testable import QwenPrime

@Suite("Tool Transport Encoding Contract Tests")
struct ToolTransportEncodingTests {

    @Test("ChatCompletionMessage and ToolDefinition encode an OpenAI-compatible request transcript")
    func testTransportModelsEncodeOpenAITranscript() throws {
        let userMessage = ChatCompletionMessage(
            role: .user,
            content: "Inspect Package.swift in the workspace."
        )

        let toolCall = ToolCall(
            id: "call_abc123",
            type: "function",
            function: ToolCall.FunctionCall(
                name: "workspace_read_file",
                arguments: "{\"path\":\"Package.swift\"}"
            )
        )

        let assistantMessage = ChatCompletionMessage(
            role: .assistant,
            content: nil,
            toolCalls: [toolCall]
        )

        let toolResponseMessage = ChatCompletionMessage(
            role: .tool,
            content: "// swift-tools-version: 6.0\nimport PackageDescription",
            toolCallId: "call_abc123"
        )

        let toolSchema = ToolDefinition(
            type: "function",
            function: ToolDefinition.FunctionDefinition(
                name: "workspace_read_file",
                description: "Read a file from workspace",
                parameters: JSONValue.object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("Relative file path")
                        ])
                    ]),
                    "required": .array([.string("path")])
                ])
            )
        )

        let transcript: [ChatCompletionMessage] = [
            userMessage,
            assistantMessage,
            toolResponseMessage
        ]

        let encoder = JSONEncoder()
        let transcriptData = try encoder.encode(transcript)
        let toolsData = try encoder.encode([toolSchema])

        guard let jsonTranscript = try JSONSerialization.jsonObject(with: transcriptData) as? [[String: Any]],
              let jsonTools = try JSONSerialization.jsonObject(with: toolsData) as? [[String: Any]] else {
            Issue.record("Failed to serialize transport transcript as JSON arrays")
            return
        }

        #expect(jsonTranscript.count == 3)

        // 1. User message
        let userDict = jsonTranscript[0]
        #expect(userDict["role"] as? String == "user")
        #expect(userDict["content"] as? String == "Inspect Package.swift in the workspace.")

        // 2. Assistant tool call message
        let assistantDict = jsonTranscript[1]
        #expect(assistantDict["role"] as? String == "assistant")
        guard let toolCallsArray = assistantDict["tool_calls"] as? [[String: Any]], toolCallsArray.count == 1 else {
            Issue.record("Expected assistant message to contain tool_calls array")
            return
        }
        let firstToolCall = toolCallsArray[0]
        #expect(firstToolCall["id"] as? String == "call_abc123")
        #expect(firstToolCall["type"] as? String == "function")
        guard let functionObj = firstToolCall["function"] as? [String: Any] else {
            Issue.record("Expected function dictionary in tool_call")
            return
        }
        #expect(functionObj["name"] as? String == "workspace_read_file")
        #expect(functionObj["arguments"] as? String == "{\"path\":\"Package.swift\"}")

        // 3. Tool response message
        let toolDict = jsonTranscript[2]
        #expect(toolDict["role"] as? String == "tool")
        #expect(toolDict["content"] as? String == "// swift-tools-version: 6.0\nimport PackageDescription")
        #expect(toolDict["tool_call_id"] as? String == "call_abc123")

        // 4. Tool definition schema
        #expect(jsonTools.count == 1)
        let firstTool = jsonTools[0]
        #expect(firstTool["type"] as? String == "function")
        guard let toolFn = firstTool["function"] as? [String: Any] else {
            Issue.record("Expected function object in tool definition")
            return
        }
        #expect(toolFn["name"] as? String == "workspace_read_file")
        #expect(toolFn["description"] as? String == "Read a file from workspace")
        guard let parameters = toolFn["parameters"] as? [String: Any] else {
            Issue.record("Expected parameters object in tool function")
            return
        }
        #expect(parameters["type"] as? String == "object")
    }
}
