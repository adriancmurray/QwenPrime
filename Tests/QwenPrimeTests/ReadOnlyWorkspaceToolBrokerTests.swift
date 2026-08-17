import Foundation
import Testing
@testable import QwenPrime

@Suite("ReadOnlyWorkspaceToolBroker Contract Tests")
struct ReadOnlyWorkspaceToolBrokerTests {

    // MARK: - Contract 1: Tool Definitions

    @Test("Broker exposes exactly two OpenAI-compatible tool definitions: workspace_list_directory and workspace_read_file")
    func testBrokerExposesExactlyTwoToolDefinitions() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let broker = ReadOnlyWorkspaceToolBroker(service: service)

            let tools = broker.tools
            #expect(tools.count == 2)

            let toolNames = Set(tools.map(\.function.name))
            #expect(toolNames == ["workspace_list_directory", "workspace_read_file"])

            for tool in tools {
                #expect(tool.type == "function")
                #expect(tool.function.description != nil)
                #expect(tool.function.description?.isEmpty == false)
            }
        }
    }

    @Test("workspace_list_directory definition has optional path parameter")
    func testListDirectoryToolDefinitionSchema() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let broker = ReadOnlyWorkspaceToolBroker(service: service)

            guard let listTool = broker.tools.first(where: { $0.function.name == "workspace_list_directory" }) else {
                Issue.record("workspace_list_directory tool definition not found")
                return
            }

            guard case .object(let params) = listTool.function.parameters else {
                Issue.record("Expected JSONValue.object for tool parameters")
                return
            }

            #expect(params["type"] == .string("object"))

            guard case .object(let properties)? = params["properties"] else {
                Issue.record("Expected properties object in tool parameters")
                return
            }

            #expect(properties["path"] != nil)

            // path is optional: required is either nil or does not contain "path"
            if case .array(let requiredFields)? = params["required"] {
                #expect(!requiredFields.contains(.string("path")))
            }
        }
    }

    @Test("workspace_read_file definition has required path parameter")
    func testReadFileToolDefinitionSchema() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let broker = ReadOnlyWorkspaceToolBroker(service: service)

            guard let readTool = broker.tools.first(where: { $0.function.name == "workspace_read_file" }) else {
                Issue.record("workspace_read_file tool definition not found")
                return
            }

            guard case .object(let params) = readTool.function.parameters else {
                Issue.record("Expected JSONValue.object for tool parameters")
                return
            }

            #expect(params["type"] == .string("object"))

            guard case .object(let properties)? = params["properties"] else {
                Issue.record("Expected properties object in tool parameters")
                return
            }

            #expect(properties["path"] != nil)

            // path is required
            guard case .array(let requiredFields)? = params["required"] else {
                Issue.record("Expected required array in tool parameters for workspace_read_file")
                return
            }
            #expect(requiredFields.contains(.string("path")))
        }
    }

    // MARK: - Contract 2: Typed Sendable/Equatable AgentToolResult

    @Test("AgentToolResult conforms to Sendable and Equatable and captures tool execution outcome")
    func testAgentToolResultContract() async throws {
        let result1 = AgentToolResult(
            callId: "call_abc123",
            toolName: "workspace_list_directory",
            content: "{\"relativePath\":\"\",\"entries\":[],\"isTruncated\":false}",
            isSuccess: true
        )

        let result2 = AgentToolResult(
            callId: "call_abc123",
            toolName: "workspace_list_directory",
            content: "{\"relativePath\":\"\",\"entries\":[],\"isTruncated\":false}",
            isSuccess: true
        )

        let result3 = AgentToolResult(
            callId: "call_def456",
            toolName: "workspace_read_file",
            content: "File not found",
            isSuccess: false
        )

        #expect(result1 == result2)
        #expect(result1 != result3)
        #expect(result1.callId == "call_abc123")
        #expect(result1.toolName == "workspace_list_directory")
        #expect(result1.isSuccess == true)
        #expect(result3.isSuccess == false)

        // Verify Sendable conformance across task boundaries
        let task = Task { () -> AgentToolResult in
            return result1
        }
        let taskResult = await task.value
        #expect(taskResult == result1)
    }

    // MARK: - Contract 3: Success Execution with Real Service & Decodable Content

    @Test("Executing workspace_list_directory on workspace root returns decodable WorkspaceDirectoryListing")
    func testExecuteListDirectoryRootSuccess() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: "README.md", content: "# Welcome")
            try fixture.createFile(at: "Package.swift", content: "// swift-tools-version: 6.0")
            try fixture.createDirectory(at: "Sources")

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let broker = ReadOnlyWorkspaceToolBroker(service: service)

            let call = ToolCall(
                id: "call_list_root",
                type: "function",
                function: ToolCall.FunctionCall(
                    name: "workspace_list_directory",
                    arguments: "{}"
                )
            )

            let result = try await broker.execute(call)

            #expect(result.callId == "call_list_root")
            #expect(result.toolName == "workspace_list_directory")
            #expect(result.isSuccess == true)

            guard let jsonData = result.content.data(using: .utf8) else {
                Issue.record("Result content was not valid UTF-8 data")
                return
            }

            let listing = try JSONDecoder().decode(WorkspaceDirectoryListing.self, from: jsonData)
            #expect(listing.relativePath == "")
            #expect(listing.isTruncated == false)
            #expect(listing.entries.count == 3)

            let entryNames = listing.entries.map(\.name)
            #expect(entryNames.contains("Package.swift"))
            #expect(entryNames.contains("README.md"))
            #expect(entryNames.contains("Sources"))
        }
    }

    @Test("Executing workspace_list_directory on subdirectory returns decodable WorkspaceDirectoryListing")
    func testExecuteListDirectorySubdirectorySuccess() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: "Sources/main.swift", content: "print(\"Hello\")")
            try fixture.createFile(at: "Sources/App.swift", content: "struct App {}")

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let broker = ReadOnlyWorkspaceToolBroker(service: service)

            let call = ToolCall(
                id: "call_list_sub",
                type: "function",
                function: ToolCall.FunctionCall(
                    name: "workspace_list_directory",
                    arguments: "{\"path\": \"Sources\"}"
                )
            )

            let result = try await broker.execute(call)

            #expect(result.callId == "call_list_sub")
            #expect(result.toolName == "workspace_list_directory")
            #expect(result.isSuccess == true)

            guard let jsonData = result.content.data(using: .utf8) else {
                Issue.record("Result content was not valid UTF-8 data")
                return
            }

            let listing = try JSONDecoder().decode(WorkspaceDirectoryListing.self, from: jsonData)
            #expect(listing.relativePath == "Sources")
            #expect(listing.entries.count == 2)
            #expect(listing.entries.map(\.name) == ["App.swift", "main.swift"])
        }
    }

    @Test("Executing workspace_read_file on text file returns decodable WorkspaceFileRead")
    func testExecuteReadFileSuccess() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let fileContent = "// Swift Source\nimport Foundation\nlet x = 42\n"
            try fixture.createFile(at: "Sources/main.swift", content: fileContent)

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let broker = ReadOnlyWorkspaceToolBroker(service: service)

            let call = ToolCall(
                id: "call_read_main",
                type: "function",
                function: ToolCall.FunctionCall(
                    name: "workspace_read_file",
                    arguments: "{\"path\": \"Sources/main.swift\"}"
                )
            )

            let result = try await broker.execute(call)

            #expect(result.callId == "call_read_main")
            #expect(result.toolName == "workspace_read_file")
            #expect(result.isSuccess == true)

            guard let jsonData = result.content.data(using: .utf8) else {
                Issue.record("Result content was not valid UTF-8 data")
                return
            }

            let fileRead = try JSONDecoder().decode(WorkspaceFileRead.self, from: jsonData)
            #expect(fileRead.relativePath == "Sources/main.swift")
            #expect(fileRead.content == fileContent)
            #expect(fileRead.byteCount == fileContent.utf8.count)
            #expect(fileRead.lineCount == 4)
            #expect(fileRead.isTruncated == false)
        }
    }

    // MARK: - Contract 4: Resilient Structured Failures (No Crashing / No Uncaught Throws)

    @Test("Malformed JSON arguments return structured failure result")
    func testMalformedJSONArgumentsReturnFailureResult() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let broker = ReadOnlyWorkspaceToolBroker(service: service)

            let malformedCalls = [
                ToolCall(id: "c1", type: "function", function: .init(name: "workspace_read_file", arguments: "not-json")),
                ToolCall(id: "c2", type: "function", function: .init(name: "workspace_read_file", arguments: "{missing_quote: 1}")),
                ToolCall(id: "c3", type: "function", function: .init(name: "workspace_list_directory", arguments: "{")),
                ToolCall(id: "c4", type: "function", function: .init(name: "workspace_list_directory", arguments: ""))
            ]

            for call in malformedCalls {
                let result = try await broker.execute(call)
                #expect(result.callId == call.id)
                #expect(result.toolName == call.function.name)
                #expect(result.isSuccess == false)
                #expect(!result.content.isEmpty)
            }
        }
    }

    @Test("Non-object JSON arguments return structured failure result")
    func testNonObjectJSONArgumentsReturnFailureResult() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let broker = ReadOnlyWorkspaceToolBroker(service: service)

            let nonObjectCalls = [
                ToolCall(id: "c1", type: "function", function: .init(name: "workspace_read_file", arguments: "[\"Sources/main.swift\"]")),
                ToolCall(id: "c2", type: "function", function: .init(name: "workspace_read_file", arguments: "\"Sources/main.swift\"")),
                ToolCall(id: "c3", type: "function", function: .init(name: "workspace_list_directory", arguments: "123")),
                ToolCall(id: "c4", type: "function", function: .init(name: "workspace_list_directory", arguments: "true")),
                ToolCall(id: "c5", type: "function", function: .init(name: "workspace_list_directory", arguments: "null"))
            ]

            for call in nonObjectCalls {
                let result = try await broker.execute(call)
                #expect(result.callId == call.id)
                #expect(result.toolName == call.function.name)
                #expect(result.isSuccess == false)
                #expect(!result.content.isEmpty)
            }
        }
    }

    @Test("Missing path argument for workspace_read_file returns structured failure result")
    func testMissingPathForReadFileReturnsFailureResult() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let broker = ReadOnlyWorkspaceToolBroker(service: service)

            let call = ToolCall(
                id: "call_missing_path",
                type: "function",
                function: ToolCall.FunctionCall(
                    name: "workspace_read_file",
                    arguments: "{}"
                )
            )

            let result = try await broker.execute(call)
            #expect(result.callId == "call_missing_path")
            #expect(result.toolName == "workspace_read_file")
            #expect(result.isSuccess == false)
            #expect(!result.content.isEmpty)
        }
    }

    @Test("Wrong path argument type returns structured failure result")
    func testWrongPathTypeReturnsFailureResult() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let broker = ReadOnlyWorkspaceToolBroker(service: service)

            let invalidPathCalls = [
                ToolCall(id: "c1", type: "function", function: .init(name: "workspace_read_file", arguments: "{\"path\": 123}")),
                ToolCall(id: "c2", type: "function", function: .init(name: "workspace_read_file", arguments: "{\"path\": [\"file.txt\"]}")),
                ToolCall(id: "c3", type: "function", function: .init(name: "workspace_read_file", arguments: "{\"path\": {\"name\": \"file.txt\"}}")),
                ToolCall(id: "c4", type: "function", function: .init(name: "workspace_list_directory", arguments: "{\"path\": true}")),
                ToolCall(id: "c5", type: "function", function: .init(name: "workspace_list_directory", arguments: "{\"path\": [\"Sources\"]}"))
            ]

            for call in invalidPathCalls {
                let result = try await broker.execute(call)
                #expect(result.callId == call.id)
                #expect(result.toolName == call.function.name)
                #expect(result.isSuccess == false)
                #expect(!result.content.isEmpty)
            }
        }
    }

    @Test("Unknown tool names return structured failure result")
    func testUnknownToolNamesReturnFailureResult() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let broker = ReadOnlyWorkspaceToolBroker(service: service)

            let unknownCalls = [
                ToolCall(id: "u1", type: "function", function: .init(name: "workspace_write_file", arguments: "{\"path\": \"test.txt\", \"content\": \"data\"}")),
                ToolCall(id: "u2", type: "function", function: .init(name: "bash", arguments: "{\"command\": \"ls -la\"}")),
                ToolCall(id: "u3", type: "function", function: .init(name: "execute_command", arguments: "{\"cmd\": \"pwd\"}")),
                ToolCall(id: "u4", type: "function", function: .init(name: "workspace_delete_file", arguments: "{\"path\": \"file.txt\"}")),
                ToolCall(id: "u5", type: "function", function: .init(name: "unknown_custom_tool", arguments: "{}"))
            ]

            for call in unknownCalls {
                let result = try await broker.execute(call)
                #expect(result.callId == call.id)
                #expect(result.toolName == call.function.name)
                #expect(result.isSuccess == false)
                #expect(!result.content.isEmpty)
            }
        }
    }

    @Test("Service access denials and security guard rejections return structured failure results")
    func testServiceAccessDenialsReturnStructuredFailures() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: "valid.txt", content: "valid")
            try fixture.createDirectory(at: "subfolder")

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let broker = ReadOnlyWorkspaceToolBroker(service: service)

            let denialCalls = [
                // Path traversal
                ToolCall(id: "d1", type: "function", function: .init(name: "workspace_read_file", arguments: "{\"path\": \"../outside.txt\"}")),
                ToolCall(id: "d2", type: "function", function: .init(name: "workspace_list_directory", arguments: "{\"path\": \"../../\"}")),
                ToolCall(id: "d3", type: "function", function: .init(name: "workspace_read_file", arguments: "{\"path\": \"/etc/passwd\"}")),
                // Secret path restriction
                ToolCall(id: "d4", type: "function", function: .init(name: "workspace_read_file", arguments: "{\"path\": \".env\"}")),
                ToolCall(id: "d5", type: "function", function: .init(name: "workspace_read_file", arguments: "{\"path\": \".git/config\"}")),
                ToolCall(id: "d6", type: "function", function: .init(name: "workspace_read_file", arguments: "{\"path\": \"id_rsa\"}")),
                ToolCall(id: "d7", type: "function", function: .init(name: "workspace_list_directory", arguments: "{\"path\": \".git\"}")),
                // Non-existent path
                ToolCall(id: "d8", type: "function", function: .init(name: "workspace_read_file", arguments: "{\"path\": \"missing_file.txt\"}")),
                ToolCall(id: "d9", type: "function", function: .init(name: "workspace_list_directory", arguments: "{\"path\": \"non_existent_dir\"}")),
                // Directory read as file
                ToolCall(id: "d10", type: "function", function: .init(name: "workspace_read_file", arguments: "{\"path\": \"subfolder\"}"))
            ]

            for call in denialCalls {
                let result = try await broker.execute(call)
                #expect(result.callId == call.id)
                #expect(result.toolName == call.function.name)
                #expect(result.isSuccess == false)
                #expect(!result.content.isEmpty)
            }
        }
    }

    @Test("Reading binary non-UTF-8 file returns structured failure result")
    func testReadingBinaryFileReturnsStructuredFailure() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let rawBytes: [UInt8] = [0x00, 0xFF, 0xFE, 0xFD, 0x80, 0x81]
            try fixture.createDataFile(at: "binary.bin", data: Data(rawBytes))

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let broker = ReadOnlyWorkspaceToolBroker(service: service)

            let call = ToolCall(
                id: "call_bin",
                type: "function",
                function: ToolCall.FunctionCall(
                    name: "workspace_read_file",
                    arguments: "{\"path\": \"binary.bin\"}"
                )
            )

            let result = try await broker.execute(call)
            #expect(result.callId == "call_bin")
            #expect(result.toolName == "workspace_read_file")
            #expect(result.isSuccess == false)
            #expect(!result.content.isEmpty)
        }
    }

    // MARK: - Contract 5: Sanitized Failure Content (No Absolute Root or File Content Leakage)

    @Test("Failure result content is sanitized and never leaks the absolute workspace root URL or restricted file content")
    func testFailureContentSanitization() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let broker = ReadOnlyWorkspaceToolBroker(service: service)

            let absoluteRootPath = fixture.rootURL.path

            let failureCalls = [
                ToolCall(id: "s1", type: "function", function: .init(name: "workspace_read_file", arguments: "{\"path\": \"../outside.txt\"}")),
                ToolCall(id: "s2", type: "function", function: .init(name: "workspace_read_file", arguments: "{\"path\": \".env\"}")),
                ToolCall(id: "s3", type: "function", function: .init(name: "workspace_read_file", arguments: "{\"path\": \"missing.txt\"}")),
                ToolCall(id: "s4", type: "function", function: .init(name: "workspace_list_directory", arguments: "{\"path\": \"../../root\"}")),
                ToolCall(id: "s5", type: "function", function: .init(name: "workspace_list_directory", arguments: "{\"path\": \".git\"}"))
            ]

            for call in failureCalls {
                let result = try await broker.execute(call)
                #expect(result.isSuccess == false)
                #expect(!result.content.contains(absoluteRootPath))
            }
        }
    }

    // MARK: - Contract 6: Cancellation Propagation

    @Test("Task cancellation propagates as CancellationError rather than returning a result")
    func testCancellationPropagatesAsCancellationError() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: "data.txt", content: "data")

            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let broker = ReadOnlyWorkspaceToolBroker(service: service)

            let call = ToolCall(
                id: "call_cancel",
                type: "function",
                function: ToolCall.FunctionCall(
                    name: "workspace_read_file",
                    arguments: "{\"path\": \"data.txt\"}"
                )
            )

            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await broker.execute(call)
            }

            do {
                _ = try await task.value
                Issue.record("Expected execute to throw CancellationError upon cancellation")
            } catch is CancellationError {
                // Expected: cancellation propagates cleanly as CancellationError
            } catch {
                Issue.record("Expected CancellationError, but received: \(error)")
            }
        }
    }

    // MARK: - Contract 7: Capability Confinement (No Write / Shell / Process / Network)

    @Test("Broker confines capabilities strictly to read-only workspace operations")
    func testBrokerHasNoWriteOrExecutionCapabilities() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let broker = ReadOnlyWorkspaceToolBroker(service: service)

            let exposedNames = broker.tools.map(\.function.name)
            #expect(!exposedNames.contains("workspace_write_file"))
            #expect(!exposedNames.contains("workspace_delete_file"))
            #expect(!exposedNames.contains("bash"))
            #expect(!exposedNames.contains("sh"))
            #expect(!exposedNames.contains("execute_command"))
            #expect(!exposedNames.contains("network_fetch"))
            #expect(!exposedNames.contains("run_process"))
            #expect(exposedNames.count == 2)
        }
    }
}
