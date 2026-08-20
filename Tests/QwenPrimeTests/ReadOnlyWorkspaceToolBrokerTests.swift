import Foundation
import Testing
@testable import QwenPrime

@Suite("ReadOnlyWorkspaceToolBroker Contract Tests")
struct ReadOnlyWorkspaceToolBrokerTests {

    // MARK: - Contract 1: Tool Definitions

    @Test("Broker exposes bounded workspace listing, reading, file discovery, and text search tools")
    func testBrokerExposesReadOnlyToolDefinitions() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let service = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let broker = ReadOnlyWorkspaceToolBroker(service: service)

            let tools = broker.tools
            #expect(tools.count == 4)

            let toolNames = Set(tools.map(\.function.name))
            #expect(toolNames == ToolName.quietWorkspaceReadTools)

            for tool in tools {
                #expect(tool.type == "function")
                #expect(tool.function.description != nil)
                #expect(tool.function.description?.isEmpty == false)
            }
        }
    }

    @Test("workspace_search_text executes through the broker and returns decodable matches")
    func testExecuteSearchTextSuccess() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: "Sources/App.swift", content: "struct PrimeApp {}\n")
            let broker = ReadOnlyWorkspaceToolBroker(
                service: try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            )
            let call = ToolCall(
                id: "call_search",
                type: "function",
                function: .init(
                    name: "workspace_search_text",
                    arguments: "{\"query\":\"PrimeApp\"}"
                )
            )

            let result = try await broker.execute(call)
            #expect(result.isSuccess == true)
            let data = try #require(result.content.data(using: .utf8))
            let search = try JSONDecoder().decode(WorkspaceTextSearchResult.self, from: data)
            #expect(search.matches.map(\.relativePath) == ["Sources/App.swift"])
            #expect(search.matches.map(\.lineNumber) == [1])
        }
    }

    @Test("workspace_find_files executes through the broker and returns regular-file matches")
    func testExecuteFindFilesSuccess() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: "Sources/PrimeFeature.swift", content: "struct Feature {}\n")
            let broker = ReadOnlyWorkspaceToolBroker(
                service: try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            )
            let call = ToolCall(
                id: "call_find",
                type: "function",
                function: .init(
                    name: "workspace_find_files",
                    arguments: "{\"query\":\"primefeature\"}"
                )
            )

            let result = try await broker.execute(call)
            #expect(result.isSuccess == true)
            let data = try #require(result.content.data(using: .utf8))
            let search = try JSONDecoder().decode(WorkspaceFileSearchResult.self, from: data)
            #expect(search.matches.map(\.relativePath) == ["Sources/PrimeFeature.swift"])
        }
    }

    @Test("workspace search tools reject missing, non-string, and whitespace-only queries")
    func testSearchToolsRejectInvalidQueries() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let broker = ReadOnlyWorkspaceToolBroker(
                service: try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            )
            let calls = [
                ToolCall(id: "missing", type: "function", function: .init(name: "workspace_find_files", arguments: "{}")),
                ToolCall(id: "number", type: "function", function: .init(name: "workspace_search_text", arguments: "{\"query\":42}")),
                ToolCall(id: "blank", type: "function", function: .init(name: "workspace_search_text", arguments: "{\"query\":\"  \"}"))
            ]

            for call in calls {
                let result = try await broker.execute(call)
                #expect(result.isSuccess == false)
                #expect(result.content.contains("query"))
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
            #expect(properties["start_line"] != nil)
            #expect(properties["end_line"] != nil)

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
            #expect(fileRead.lineCount == 3)
            #expect(fileRead.isTruncated == false)
        }
    }

    @Test("workspace_read_file forwards optional 1-based inclusive line range arguments")
    func testExecuteReadFileLineRange() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(
                at: "Sources/range.swift",
                content: (1...8).map { "let value\($0) = \($0)" }.joined(separator: "\n")
            )
            let broker = ReadOnlyWorkspaceToolBroker(
                service: try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            )
            let call = ToolCall(
                id: "call_read_range",
                type: "function",
                function: ToolCall.FunctionCall(
                    name: "workspace_read_file",
                    arguments: "{\"path\":\"Sources/range.swift\",\"start_line\":3,\"end_line\":4}"
                )
            )

            let result = try await broker.execute(call)
            #expect(result.isSuccess == true)
            let data = try #require(result.content.data(using: .utf8))
            let read = try JSONDecoder().decode(WorkspaceFileRead.self, from: data)
            #expect(read.content == "let value3 = 3\nlet value4 = 4\n")
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

            let workspacePaths = WorkspacePathSanitizer.pathVariants(
                for: fixture.rootURL
            )

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
                for path in workspacePaths where !path.isEmpty {
                    #expect(!result.content.contains(path))
                }
            }
        }
    }

    @Test("Path sanitizer redacts raw standardized and symlink-resolved roots")
    func testPathSanitizerHandlesEveryRootRepresentation() throws {
        let fixture = try WorkspaceTestFixture()
        defer { fixture.tearDown() }
        let realParent = try fixture.createDirectory(at: "real")
        let realWorkspace = realParent.appendingPathComponent(
            "workspace",
            isDirectory: true
        )
        let realTemporary = realParent.appendingPathComponent(
            "task-temp",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: realWorkspace.appendingPathComponent(
                "nested",
                isDirectory: true
            ),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: realTemporary.appendingPathComponent(
                "nested",
                isDirectory: true
            ),
            withIntermediateDirectories: true
        )
        let workspaceAlias = fixture.rootURL.appendingPathComponent(
            "workspace-alias",
            isDirectory: true
        )
        let temporaryAlias = fixture.rootURL.appendingPathComponent(
            "temp-alias",
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: workspaceAlias,
            withDestinationURL: realWorkspace
        )
        try FileManager.default.createSymbolicLink(
            at: temporaryAlias,
            withDestinationURL: realTemporary
        )
        let rawWorkspace = URL(
            fileURLWithPath: "\(workspaceAlias.path)/nested/..",
            isDirectory: true
        )
        let rawTemporary = URL(
            fileURLWithPath: "\(temporaryAlias.path)/nested/..",
            isDirectory: true
        )
        let workspacePaths = WorkspacePathSanitizer.pathVariants(
            for: rawWorkspace
        )
        let temporaryPaths = WorkspacePathSanitizer.pathVariants(
            for: rawTemporary
        )
        let sanitizer = WorkspacePathSanitizer(
            workspaceRoot: rawWorkspace,
            temporaryRoot: rawTemporary
        )

        #expect(workspacePaths[0] != workspacePaths[1])
        #expect(workspacePaths[0] != workspacePaths[2])
        #expect(temporaryPaths[0] != temporaryPaths[1])
        #expect(temporaryPaths[0] != temporaryPaths[2])
        let sanitized = sanitizer.sanitize(
            (workspacePaths + temporaryPaths).joined(separator: " | ")
        )
        #expect(sanitized.contains("<workspace_root>"))
        #expect(sanitized.contains("<task_temp>"))
        for path in Set(workspacePaths + temporaryPaths) where !path.isEmpty {
            #expect(!sanitized.contains(path))
        }
    }

    @Test("Filesystem root is preserved while task temporary paths are redacted")
    func testPathSanitizerDoesNotReplaceEverySlash() throws {
        let fixture = try WorkspaceTestFixture()
        defer { fixture.tearDown() }
        let sanitizer = WorkspacePathSanitizer(
            workspaceRoot: URL(fileURLWithPath: "/", isDirectory: true),
            temporaryRoot: fixture.rootURL
        )
        let safeText = "url=https://example.com/a/b executable=/usr/bin/swift"
        let sanitized = sanitizer.sanitize(
            "\(safeText) temp=\(fixture.rootURL.path)"
        )

        #expect(sanitized.contains(safeText))
        #expect(sanitized.contains("temp=<task_temp>"))
        #expect(!sanitized.contains(fixture.rootURL.path))
        #expect(!sanitized.contains("<workspace_root>"))
    }

    @Test(
        "Path sanitizer matches macOS path casing without corrupting safe text"
    )
    func testPathSanitizerMatchesPathsCaseInsensitively() {
        let workspacePath = "/Users/Alice/Developer/QwenPrime"
        let temporaryPath = "\(workspacePath)/.build/Task-ABC"
        let sanitizer = WorkspacePathSanitizer(
            workspaceRoot: URL(
                fileURLWithPath: workspacePath,
                isDirectory: true
            ),
            temporaryRoot: URL(
                fileURLWithPath: temporaryPath,
                isDirectory: true
            )
        )
        let safeText = "url=https://example.com/a/b executable=/usr/bin/swift"
        let sanitized = sanitizer.sanitize(
            """
            exact=\(workspacePath)/README.md
            lower=\(workspacePath.lowercased())/Sources/App.swift
            upper=\(workspacePath.uppercased())/Tests/AppTests.swift
            mixed=/uSeRs/aLiCe/dEvElOpEr/qWeNpRiMe/Package.swift
            tempLower=\(temporaryPath.lowercased())/stdout.txt
            tempUpper=\(temporaryPath.uppercased())/stderr.txt
            \(safeText) label=QwenPrime owner=Alice
            """
        )

        #expect(sanitized.contains("exact=<workspace_root>/README.md"))
        #expect(sanitized.contains("lower=<workspace_root>/Sources/App.swift"))
        #expect(sanitized.contains("upper=<workspace_root>/Tests/AppTests.swift"))
        #expect(sanitized.contains("mixed=<workspace_root>/Package.swift"))
        #expect(sanitized.contains("tempLower=<task_temp>/stdout.txt"))
        #expect(sanitized.contains("tempUpper=<task_temp>/stderr.txt"))
        #expect(sanitized.contains(safeText))
        #expect(sanitized.contains("label=QwenPrime owner=Alice"))
    }

    @Test("Path sanitizer requires a component boundary after a root")
    func testPathSanitizerPreservesSiblingPrefixes() {
        let workspacePath = "/Users/Alice/Developer/QwenPrime"
        let sanitizer = WorkspacePathSanitizer(
            workspaceRoot: URL(
                fileURLWithPath: workspacePath,
                isDirectory: true
            ),
            temporaryRoot: URL(fileURLWithPath: "/tmp/QwenPrime-task")
        )
        let sanitized = sanitizer.sanitize(
            """
            exact=/uSeRs/aLiCe/dEvElOpEr/qWeNpRiMe
            child=file:///USERS/ALICE/DEVELOPER/QWENPRIME/Sources/App.swift
            query=file:///users/alice/developer/qwenprime?view=tree
            sibling=/Users/Alice/Developer/QwenPrime_backup
            siblingChild=/Users/Alice/Developer/QwenPrime_backup/Sources/App.swift
            """
        )

        #expect(sanitized.contains("exact=<workspace_root>"))
        #expect(
            sanitized.contains(
                "child=file://<workspace_root>/Sources/App.swift"
            )
        )
        #expect(
            sanitized.contains("query=file://<workspace_root>?view=tree")
        )
        #expect(sanitized.contains("sibling=\(workspacePath)_backup"))
        #expect(
            sanitized.contains(
                "siblingChild=\(workspacePath)_backup/Sources/App.swift"
            )
        )
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
            #expect(exposedNames.count == 4)
        }
    }
}
