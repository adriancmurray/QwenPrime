import Foundation
import Testing
@testable import QwenPrime

@Suite("MCP tool provider")
struct MCPToolProviderTests {
    private struct RemoteCallFailure: LocalizedError, Sendable {
        let detail: String

        var errorDescription: String? { detail }
    }

    private struct AlwaysApproveRequester: WorkspaceApprovalRequesting {
        func requestApproval(
            call: ToolCall,
            payload: WorkspaceApprovalPayload
        ) async throws -> ToolApprovalDecision {
            .approve
        }
    }

    private actor FakeMCPClient: MCPClientServing {
        let discoveredTools: [MCPRemoteTool]
        let callFailure: RemoteCallFailure?
        private(set) var calls: [(String, [String: JSONValue])] = []

        init(
            discoveredTools: [MCPRemoteTool],
            callFailure: RemoteCallFailure? = nil
        ) {
            self.discoveredTools = discoveredTools
            self.callFailure = callFailure
        }

        func listTools() async throws -> [MCPRemoteTool] {
            discoveredTools
        }

        func callTool(
            name: String,
            arguments: [String: JSONValue]
        ) async throws -> MCPRemoteToolResult {
            calls.append((name, arguments))
            if let callFailure {
                throw callFailure
            }
            return MCPRemoteToolResult(content: "remote result", isError: false)
        }

        func recordedCalls() -> [(String, [String: JSONValue])] { calls }
    }

    @Test("Only loopback Streamable HTTP endpoints are accepted")
    func validatesLocalEndpoint() throws {
        let loopbackEndpoints = [
            "http://localhost:8765/mcp",
            "http://127.0.0.1:8765/mcp",
            "http://127.42.5.9:8765/mcp",
            "http://127.255.255.255:8765/mcp",
            "http://[::1]:8765/mcp",
            "http://[0:0:0:0:0:0:0:1]:8765/mcp",
            "http://[::1%25lo0]:8765/mcp",
            "http://[0:0:0:0:0:0:0:1%251]:8765/mcp",
        ]
        for (index, endpoint) in loopbackEndpoints.enumerated() {
            let configuration = try MCPServerConfiguration(
                id: "docs-\(index)",
                displayName: "Local Docs \(index)",
                endpoint: endpoint
            )
            #expect(configuration.endpoint.absoluteString == endpoint)
        }
        let pastedConfiguration = try MCPServerConfiguration(
            id: "pasted",
            displayName: "Pasted Local Docs",
            endpoint: " \n\thttp://localhost:8765/MCP\t \n"
        )
        #expect(
            pastedConfiguration.endpoint.absoluteString
                == "http://localhost:8765/MCP"
        )

        let nonLoopbackEndpoints = [
            "https://example.com/mcp",
            "http://126.255.255.255:8765/mcp",
            "http://128.0.0.1:8765/mcp",
            "http://127.0.0.999:8765/mcp",
            "http://192.168.1.2:8765/mcp",
            "http://[::]:8765/mcp",
            "http://[::2]:8765/mcp",
            "http://[::1::]:8765/mcp",
            "http://[::ffff:127.0.0.1]:8765/mcp",
            "http://[fe80::1%25lo0]:8765/mcp",
            "http://[::1%25]:8765/mcp",
            "http://[::1%25bad%25scope]:8765/mcp",
            " \n https://example.com/mcp \t",
        ]
        for (index, endpoint) in nonLoopbackEndpoints.enumerated() {
            #expect(throws: MCPServerConfigurationError.nonLoopbackEndpoint) {
                _ = try MCPServerConfiguration(
                    id: "remote-\(index)",
                    displayName: "Remote \(index)",
                    endpoint: endpoint
                )
            }
        }
        #expect(throws: MCPServerConfigurationError.invalidEndpoint) {
            _ = try MCPServerConfiguration(
                id: "ftp",
                displayName: "FTP",
                endpoint: "ftp://127.0.0.1:8765/mcp"
            )
        }
        #expect(throws: MCPServerConfigurationError.invalidEndpoint) {
            _ = try MCPServerConfiguration(
                id: "credentialed",
                displayName: "Credentialed",
                endpoint: "http://user:password@localhost:8765/mcp"
            )
        }
        #expect(throws: MCPServerConfigurationError.invalidEndpoint) {
            _ = try MCPServerConfiguration(
                id: "malformed",
                displayName: "Malformed",
                endpoint: "not a URL"
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
        #expect(
            registration.tools[0].definition.function.name
                == ToolName.mcp(provider: "docs", tool: "lookup_weather")
        )
        #expect(registration.tools[0].authorization == .userApproval)
        #expect(registration.tools[0].definition.function.parameters == sampleTool.inputSchema)
    }

    @Test("Discovery rejects remote tool names that collide after namespacing")
    func discoveryRejectsSluggifiedNameCollisions() async throws {
        let collisionTools = [
            MCPRemoteTool(
                name: "lookup.weather",
                description: nil,
                inputSchema: .object(["type": .string("object")])
            ),
            MCPRemoteTool(
                name: "lookup weather",
                description: nil,
                inputSchema: .object(["type": .string("object")])
            ),
        ]
        let client = FakeMCPClient(discoveredTools: collisionTools)

        await #expect(
            throws: MCPToolProviderError.duplicateToolName(
                ToolName.mcp(provider: "docs", tool: "lookup_weather")
            )
        ) {
            _ = try await MCPToolProvider.connect(
                configuration: configuration,
                client: client,
                approvalRequester: nil
            )
        }
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

    @Test("Malformed and non-object MCP arguments fail validation")
    func invalidArgumentsFailWithoutCallingRemoteTool() async throws {
        let client = FakeMCPClient(discoveredTools: [sampleTool])
        let registration = try await MCPToolProvider.connect(
            configuration: configuration,
            client: client,
            approvalRequester: AlwaysApproveRequester()
        )

        for (id, arguments) in [
            ("malformed", #"{"city":"Boise""#),
            ("array", #"["Boise"]"#),
        ] {
            let result = try await registration.executor.execute(
                namespacedCall(id: id, arguments: arguments)
            )

            #expect(!result.isSuccess)
            #expect(
                result.content
                    == "MCP tool arguments must be a JSON object."
            )
            #expect(result.approvalState == nil)
        }
        #expect(await client.recordedCalls().isEmpty)
    }

    @Test("Unknown MCP tool names fail without reaching the remote client")
    func unknownToolFails() async throws {
        let client = FakeMCPClient(discoveredTools: [sampleTool])
        let registration = try await MCPToolProvider.connect(
            configuration: configuration,
            client: client,
            approvalRequester: AlwaysApproveRequester()
        )
        let call = namespacedCall(
            id: "unknown",
            name: "mcp__docs__missing"
        )

        let result = try await registration.executor.execute(call)

        #expect(!result.isSuccess)
        #expect(result.content == "Unknown MCP tool: mcp__docs__missing")
        #expect(result.approvalState == nil)
        #expect(await client.recordedCalls().isEmpty)
    }

    @Test("Missing MCP approval requester fails without remote execution")
    func missingApprovalRequesterFails() async throws {
        let client = FakeMCPClient(discoveredTools: [sampleTool])
        let registration = try await MCPToolProvider.connect(
            configuration: configuration,
            client: client,
            approvalRequester: nil
        )

        let result = try await registration.executor.execute(
            namespacedCall(id: "missing-approval")
        )

        #expect(!result.isSuccess)
        #expect(result.content == "External tool approval is unavailable.")
        #expect(result.approvalState == nil)
        #expect(await client.recordedCalls().isEmpty)
    }

    @Test("Approved remote MCP failure returns a generic failed result")
    func remoteCallFailureIsUnsuccessful() async throws {
        let sensitiveDetail =
            "token=private-mcp-secret at /Users/private/config.json"
        let client = FakeMCPClient(
            discoveredTools: [sampleTool],
            callFailure: RemoteCallFailure(detail: sensitiveDetail)
        )
        let registration = try await MCPToolProvider.connect(
            configuration: configuration,
            client: client,
            approvalRequester: AlwaysApproveRequester()
        )

        let result = try await registration.executor.execute(
            namespacedCall(id: "remote-failure")
        )

        #expect(!result.isSuccess)
        #expect(result.content == "MCP tool call failed.")
        #expect(!result.content.contains(sensitiveDetail))
        #expect(result.approvalState == .failed)
        #expect(await client.recordedCalls().count == 1)
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

    private func namespacedCall(
        id: String,
        name: String = "mcp__docs__lookup_weather",
        arguments: String = #"{"city":"Boise"}"#
    ) -> ToolCall {
        ToolCall(
            id: id,
            function: .init(
                name: name,
                arguments: arguments
            )
        )
    }
}
