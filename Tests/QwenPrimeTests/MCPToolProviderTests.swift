import Foundation
import Testing
@testable import QwenPrime

@Suite("MCP tool provider")
struct MCPToolProviderTests {
    actor FakeMCPClient: MCPClientServing {
        let discoveredTools: [MCPRemoteTool]
        private(set) var calls: [(String, [String: JSONValue])] = []

        init(discoveredTools: [MCPRemoteTool]) {
            self.discoveredTools = discoveredTools
        }

        func listTools() async throws -> [MCPRemoteTool] {
            discoveredTools
        }

        func callTool(
            name: String,
            arguments: [String: JSONValue]
        ) async throws -> MCPRemoteToolResult {
            calls.append((name, arguments))
            return MCPRemoteToolResult(content: "remote result", isError: false)
        }

        func recordedCalls() -> [(String, [String: JSONValue])] { calls }
    }

    @Test("Only loopback Streamable HTTP endpoints are accepted")
    func validatesLocalEndpoint() throws {
        _ = try MCPServerConfiguration(
            id: "docs",
            displayName: "Local Docs",
            endpoint: "http://127.0.0.1:8765/mcp"
        )

        #expect(throws: MCPServerConfigurationError.nonLoopbackEndpoint) {
            _ = try MCPServerConfiguration(
                id: "remote",
                displayName: "Remote",
                endpoint: "https://example.com/mcp"
            )
        }
    }

    @Test("Discovery namespaces tools and marks them for user approval")
    func discoveryProducesGuardedRegistration() async throws {
        let client = FakeMCPClient(discoveredTools: [sampleTool])
        let registration = try await MCPToolProvider.connect(
            configuration: configuration,
            client: client,
            approvalRequester: nil
        )

        #expect(registration.id == "mcp.docs")
        #expect(registration.displayName == "Local Docs")
        #expect(registration.tools.count == 1)
        #expect(registration.tools[0].definition.function.name == "mcp__docs__lookup_weather")
        #expect(registration.tools[0].authorization == .userApproval)
        #expect(registration.tools[0].definition.function.parameters == sampleTool.inputSchema)
    }

    @Test("Rejected MCP calls never reach the server")
    @MainActor
    func rejectedCallDoesNotExecute() async throws {
        let coordinator = WorkspaceApprovalCoordinator()
        let requester = ConversationWorkspaceApprovalRequester(
            coordinator: coordinator,
            conversationID: UUID(),
            messageID: UUID()
        )
        let client = FakeMCPClient(discoveredTools: [sampleTool])
        let registration = try await MCPToolProvider.connect(
            configuration: configuration,
            client: client,
            approvalRequester: requester
        )
        let call = namespacedCall(id: "reject-1")
        let task = Task { try await registration.executor.execute(call) }

        try await AsyncCondition.wait(description: "MCP approval pending") {
            coordinator.pendingRequests.count == 1
        }
        let request = try #require(coordinator.pendingRequests.first)
        guard case .externalTool(let proposal) = request.payload else {
            Issue.record("Expected external MCP tool approval")
            return
        }
        #expect(proposal.providerDisplayName == "Local Docs")
        #expect(proposal.toolName == "lookup.weather")
        #expect(coordinator.resolve(request.id, decision: .reject))

        let result = try await task.value
        #expect(!result.isSuccess)
        #expect(result.approvalState == .rejected)
        #expect(await client.recordedCalls().isEmpty)
    }

    @Test("Approved MCP calls execute the original remote name and arguments")
    @MainActor
    func approvedCallExecutes() async throws {
        let coordinator = WorkspaceApprovalCoordinator()
        let requester = ConversationWorkspaceApprovalRequester(
            coordinator: coordinator,
            conversationID: UUID(),
            messageID: UUID()
        )
        let client = FakeMCPClient(discoveredTools: [sampleTool])
        let registration = try await MCPToolProvider.connect(
            configuration: configuration,
            client: client,
            approvalRequester: requester
        )
        let call = namespacedCall(id: "approve-1")
        let task = Task { try await registration.executor.execute(call) }

        try await AsyncCondition.wait(description: "MCP approval pending") {
            coordinator.pendingRequests.count == 1
        }
        let request = try #require(coordinator.pendingRequests.first)
        #expect(coordinator.resolve(request.id, decision: .approve))

        let result = try await task.value
        #expect(result.isSuccess)
        #expect(result.content == "remote result")
        #expect(result.approvalState == .approved)
        let calls = await client.recordedCalls()
        #expect(calls.count == 1)
        #expect(calls[0].0 == "lookup.weather")
        #expect(calls[0].1 == ["city": .string("Boise")])
    }

    private var configuration: MCPServerConfiguration {
        get throws {
            try MCPServerConfiguration(
                id: "docs",
                displayName: "Local Docs",
                endpoint: "http://127.0.0.1:8765/mcp"
            )
        }
    }

    private var sampleTool: MCPRemoteTool {
        MCPRemoteTool(
            name: "lookup.weather",
            description: "Look up local weather",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "city": .object(["type": .string("string")])
                ])
            ])
        )
    }

    private func namespacedCall(id: String) -> ToolCall {
        ToolCall(
            id: id,
            function: .init(
                name: "mcp__docs__lookup_weather",
                arguments: #"{"city":"Boise"}"#
            )
        )
    }
}
