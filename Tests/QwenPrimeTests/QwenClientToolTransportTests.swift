import Testing
import Foundation
@testable import QwenPrime

@Suite("QwenClient Tool Transport Tests", .serialized)
struct QwenClientToolTransportTests {

    @Test("SSE byte decoder preserves Unicode split across transport chunks")
    func testSSEByteDecoderPreservesSplitUnicode() {
        let expectedContent = "⚙️ Runtime Architecture"
        let line = """
        data: {"choices":[{"delta":{"content":"\(expectedContent)"},"finish_reason":null}]}
        """
        var decoder = SSELineDecoder()
        var decodedLines: [String] = []

        for byte in Array(line.utf8) + [0x0A] {
            if let decodedLine = decoder.append(byte) {
                decodedLines.append(decodedLine)
            }
        }

        #expect(decodedLines == [line])
        #expect(decodedLines.first?.contains(expectedContent) == true)
        #expect(decodedLines.first?.contains("\u{FFFD}") == false)
    }

    @Test("QwenClient tool-enabled streaming API sends structured tools in JSON request body")
    func testToolEnabledStreamingSendsToolsPayload() async throws {
        let session = TransportTestHelpers.makeTestSession()
        let client = QwenClient(session: session)

        let tool = ToolDefinition(
            type: "function",
            function: ToolDefinition.FunctionDefinition(
                name: "workspace_read_file",
                description: "Read file contents",
                parameters: JSONValue.object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("path")])
                ])
            )
        )

        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .user, content: "Check Package.swift")
        ]

        let ssePayload = """
        data: {"id":"chatcmpl-test","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

        data: {"id":"chatcmpl-test","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

        data: [DONE]

        """

        TransportTestURLProtocol.requestHandler = { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"]) else {
                throw URLError(.badServerResponse)
            }
            return (response, Data(ssePayload.utf8))
        }

        let stream = await client.streamChat(
            messages: messages,
            tools: [tool]
        )

        for try await _ in stream {}

        let requests = TransportTestURLProtocol.capturedRequests
        guard let request = requests.first else {
            Issue.record("No request was captured by TransportTestURLProtocol")
            return
        }

        #expect(request.url?.path.hasSuffix("/chat/completions") == true)
        #expect(request.httpMethod == "POST")

        guard let bodyData = TransportTestHelpers.extractRequestBodyData(from: request),
              let jsonBody = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            Issue.record("Failed to parse outgoing request JSON body")
            return
        }

        guard let toolsArray = jsonBody["tools"] as? [[String: Any]], toolsArray.count == 1 else {
            Issue.record("Expected 'tools' array with 1 tool definition in request body")
            return
        }

        #expect(toolsArray[0]["type"] as? String == "function")
        if let fn = toolsArray[0]["function"] as? [String: Any] {
            #expect(fn["name"] as? String == "workspace_read_file")
        } else {
            Issue.record("Expected 'function' object in tools definition")
        }
    }

    @Test("Existing ordinary QwenClient.streamChat sends no tools key when tools are absent")
    func testOrdinaryStreamChatSendsNoToolsKey() async throws {
        let session = TransportTestHelpers.makeTestSession()
        let client = QwenClient(session: session)

        let ordinaryMessages = [
            ChatMessage(role: .user, content: "Explain actor reentrancy in Swift")
        ]

        let ssePayload = """
        data: {"id":"chatcmpl-ord","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":"Actor"},"finish_reason":null}]}

        data: {"id":"chatcmpl-ord","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

        data: [DONE]

        """

        TransportTestURLProtocol.requestHandler = { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"]) else {
                throw URLError(.badServerResponse)
            }
            return (response, Data(ssePayload.utf8))
        }

        let stream = await client.streamChat(messages: ordinaryMessages)
        for try await _ in stream {}

        guard let request = TransportTestURLProtocol.capturedRequests.first,
              let bodyData = TransportTestHelpers.extractRequestBodyData(from: request),
              let jsonBody = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            Issue.record("Failed to capture ordinary chat request body")
            return
        }

        // Must NOT contain tools key
        #expect(jsonBody["tools"] == nil)
        #expect(jsonBody["model"] as? String == "qwen3.8-27b")

        guard let messagesArray = jsonBody["messages"] as? [[String: Any]] else {
            Issue.record("Expected messages array in ordinary chat request")
            return
        }
        #expect(messagesArray.count >= 1)
        #expect(messagesArray.last?["role"] as? String == "user")
        #expect(messagesArray.last?["content"] as? String == "Explain actor reentrancy in Swift")
    }

    @Test("Fragmented SSE tool_calls with preceding raw <tool_call> markup are accumulated as StreamEvent.toolCall without leaking raw contentDelta")
    func testFragmentedSSEToolCallsAccumulationWithRawMarkupSuppression() async throws {
        let session = TransportTestHelpers.makeTestSession()
        let client = QwenClient(session: session)

        let tool = ToolDefinition(
            type: "function",
            function: ToolDefinition.FunctionDefinition(
                name: "workspace_read_file",
                description: "Read file contents",
                parameters: nil
            )
        )

        let messages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: .user, content: "Read Package.swift")
        ]

        // SSE chunks include:
        // 1. Initial assistant role chunk
        // 2. Raw content fragments forming a <tool_call> block before the structured delta
        // 3. Fragmented structured tool_calls deltas
        // 4. Finish reason tool_calls
        let sseChunks = """
        data: {"id":"chatcmpl-tool-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}

        data: {"id":"chatcmpl-tool-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"<tool_call>\\n<function=workspace_read_file>\\n{\\"path\\": \\""},"finish_reason":null}]}

        data: {"id":"chatcmpl-tool-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Package.swift\\"}\\n</tool_call>"},"finish_reason":null}]}

        data: {"id":"chatcmpl-tool-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_12345","type":"function","function":{"name":"workspace_read_file","arguments":"{\\"path\\": \\""}}]},"finish_reason":null}]}

        data: {"id":"chatcmpl-tool-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"Package.swift\\"}"}}]},"finish_reason":null}]}

        data: {"id":"chatcmpl-tool-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

        data: [DONE]

        """

        TransportTestURLProtocol.requestHandler = { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"]) else {
                throw URLError(.badServerResponse)
            }
            return (response, Data(sseChunks.utf8))
        }

        let stream = await client.streamChat(
            messages: messages,
            tools: [tool]
        )

        var collectedEvents: [StreamEvent] = []
        for try await event in stream {
            collectedEvents.append(event)
        }

        // 1. Assert none of the raw markup, tool name, or arguments is emitted as contentDelta
        let contentDeltas = collectedEvents.compactMap { event -> String? in
            if case .contentDelta(let text) = event { return text }
            return nil
        }
        let joinedContent = contentDeltas.joined()
        #expect(!joinedContent.contains("<tool_call>"))
        #expect(!joinedContent.contains("</tool_call>"))
        #expect(!joinedContent.contains("<function="))
        #expect(!joinedContent.contains("workspace_read_file"))
        #expect(!joinedContent.contains("Package.swift"))
        #expect(!joinedContent.contains("path"))

        // 2. Assert fragmented tool_calls arguments were accumulated and emitted once as structured StreamEvent.toolCall
        let toolCallEvents = collectedEvents.compactMap { event -> ToolCall? in
            if case .toolCall(let toolCall) = event { return toolCall }
            return nil
        }

        #expect(toolCallEvents.count == 1)
        if let firstCall = toolCallEvents.first {
            #expect(firstCall.id == "call_12345")
            #expect(firstCall.type == "function")
            #expect(firstCall.function.name == "workspace_read_file")
            #expect(firstCall.function.arguments == "{\"path\": \"Package.swift\"}")
        }

        #expect(collectedEvents.contains(.finished))
    }

    @Test("Tool identity with empty arguments starts telemetry without tokens")
    func testEmptyToolArgumentsStartTelemetryWithoutTokens() async throws {
        let session = TransportTestHelpers.makeTestSession()
        let client = QwenClient(session: session)
        let tool = AgentLoopTestHelpers.sampleWorkspaceReadTool()
        let ssePayload = """
        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_empty","type":"function","function":{"name":"workspace_read_file","arguments":""}}]},"finish_reason":null}]}

        data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}

        data: [DONE]

        """

        TransportTestURLProtocol.requestHandler = { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                  ) else {
                throw URLError(.badServerResponse)
            }
            return (response, Data(ssePayload.utf8))
        }

        let stream = await client.streamChat(
            messages: [ChatCompletionMessage(role: .user, content: "Read a file")],
            tools: [tool]
        )
        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        let usageEvents = events.compactMap { event -> GenerationStats? in
            guard case .usage(let stats) = event else { return nil }
            return stats
        }
        let toolCalls = events.compactMap { event -> ToolCall? in
            guard case .toolCall(let toolCall) = event else { return nil }
            return toolCall
        }

        #expect(usageEvents.count == 2)
        let liveUsage = try #require(usageEvents.first)
        #expect(liveUsage.isThroughputEstimated == true)
        #expect(liveUsage.completionTokens == 0)
        #expect(liveUsage.timeToFirstTokenSeconds.isFinite)
        #expect(liveUsage.timeToFirstTokenSeconds >= 0)
        #expect(usageEvents.last?.isThroughputEstimated == false)
        #expect(usageEvents.last?.completionTokens == 0)
        #expect(toolCalls.first?.function.arguments == "")
    }

    @Test("Fragmented reasoning content and tool arguments share one estimate")
    func testStreamingCompletionEstimateIsChunkInvariant() async throws {
        let session = TransportTestHelpers.makeTestSession()
        let client = QwenClient(session: session)
        let tool = AgentLoopTestHelpers.sampleWorkspaceReadTool()
        let ssePayload = """
        data: {"choices":[{"delta":{"reasoning_content":""},"finish_reason":null}]}

        data: {"choices":[{"delta":{"reasoning_content":"a"},"finish_reason":null}]}

        data: {"choices":[{"delta":{"reasoning_content":"bc"},"finish_reason":null}]}

        data: {"choices":[{"delta":{"content":""},"finish_reason":null}]}

        data: {"choices":[{"delta":{"content":"d"},"finish_reason":null}]}

        data: {"choices":[{"delta":{"content":"ef"},"finish_reason":null}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_fragmented","type":"function","function":{"name":"workspace_read_file","arguments":""}}]},"finish_reason":null}]}

        data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"g"}}]},"finish_reason":null}]}

        data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}

        data: [DONE]

        """

        TransportTestURLProtocol.requestHandler = { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                  ) else {
                throw URLError(.badServerResponse)
            }
            return (response, Data(ssePayload.utf8))
        }

        let stream = await client.streamChat(
            messages: [ChatCompletionMessage(role: .user, content: "Use a tool")],
            tools: [tool]
        )
        var usageEvents: [GenerationStats] = []
        for try await event in stream {
            guard case .usage(let stats) = event else { continue }
            usageEvents.append(stats)
        }

        #expect(!usageEvents.isEmpty)
        #expect(
            usageEvents.map(\.completionTokens) == [1, 1, 1, 2, 2, 2, 2]
        )
        #expect(
            usageEvents.last?.completionTokens
                == TokenEstimation.characterBasedCount(for: "abcdefg")
        )
    }

    @Test("Tool-enabled content streams angle brackets and JSON escapes without coalescing")
    func testToolEnabledOrdinaryContentStreamsImmediatelyAndDecoded() async throws {
        let session = TransportTestHelpers.makeTestSession()
        let client = QwenClient(session: session)
        let tool = AgentLoopTestHelpers.sampleWorkspaceReadTool()
        let ssePayload = """
        data: {"choices":[{"delta":{"content":"<T>"},"finish_reason":null}]}

        data: {"choices":[{"delta":{"content":"\\\"quoted\\\"\\nline"},"finish_reason":null}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        data: [DONE]

        """

        TransportTestURLProtocol.requestHandler = { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                  ) else {
                throw URLError(.badServerResponse)
            }
            return (response, Data(ssePayload.utf8))
        }

        let stream = await client.streamChat(
            messages: [ChatCompletionMessage(role: .user, content: "Explain T")],
            tools: [tool]
        )
        var deltas: [String] = []
        for try await event in stream {
            if case .contentDelta(let text) = event {
                deltas.append(text)
            }
        }

        #expect(deltas == ["<T>", "\"quoted\"\nline"])
    }

    @Test("QwenAgentInferenceAdapter conforms to AgentInferenceStreaming and forwards configuration and messages to QwenClient using AgentRunConfiguration.baseURL exactly")
    func testQwenAgentInferenceAdapterForwardsToClient() async throws {
        let session = TransportTestHelpers.makeTestSession()
        let client = QwenClient(session: session)
        let adapter = QwenAgentInferenceAdapter(client: client)

        let tool = AgentLoopTestHelpers.sampleWorkspaceReadTool()
        let messages = [
            ChatCompletionMessage(role: .user, content: "Check configuration")
        ]
        let customBaseURL = "http://custom-inference.internal:9090/custom-api/v1"
        let config = AgentRunConfiguration(
            systemPrompt: "You are a test agent.",
            maxTurns: 5,
            baseURL: customBaseURL,
            temperature: 0.2,
            model: "qwen3.8-27b",
            isThinkingEnabled: true,
            maxCompletionTokens: 512,
            maxReasoningTokens: 64
        )

        let ssePayload = """
        data: {"id":"chatcmpl-adapter-test","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":"Adapter output"},"finish_reason":null}]}

        data: {"id":"chatcmpl-adapter-test","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

        data: [DONE]

        """

        TransportTestURLProtocol.requestHandler = { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"]) else {
                throw URLError(.badServerResponse)
            }
            return (response, Data(ssePayload.utf8))
        }

        let stream = try await adapter.streamChat(
            messages: messages,
            tools: [tool],
            configuration: config
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        #expect(events.contains { if case .contentDelta(let t) = $0 { return t == "Adapter output" } else { return false } })
        #expect(events.contains(.finished))

        // Verify captured HTTP request from QwenClient uses AgentRunConfiguration.baseURL exactly
        guard let request = TransportTestURLProtocol.capturedRequests.first else {
            Issue.record("Failed to capture request from adapter call")
            return
        }

        #expect(request.url?.absoluteString == "\(customBaseURL)/chat/completions")
        #expect(request.url?.host == "custom-inference.internal")
        #expect(request.url?.port == 9090)
        #expect(request.url?.path == "/custom-api/v1/chat/completions")

        guard let bodyData = TransportTestHelpers.extractRequestBodyData(from: request),
              let jsonBody = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            Issue.record("Failed to capture request body from adapter call")
            return
        }

        #expect(jsonBody["model"] as? String == "qwen3.8-27b")
        #expect(jsonBody["temperature"] as? Double == 0.2)
        #expect(jsonBody["max_completion_tokens"] as? Int == 512)
        #expect(jsonBody["max_reasoning_tokens"] as? Int == 64)
        #expect(jsonBody["tools"] != nil)
    }
}
