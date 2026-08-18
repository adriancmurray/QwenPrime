import Foundation
import MCP
import Testing
@testable import QwenPrime

@Suite("MCP value bridge")
struct MCPValueBridgeTests {
    @Test("MCP schemas preserve recursive JSON values")
    func mcpToTransportJSON() {
        let value = MCP.Value.object([
            "type": .string("object"),
            "required": .array([.string("query")]),
            "limit": .int(5),
            "enabled": .bool(true)
        ])

        #expect(MCPValueBridge.jsonValue(from: value) == .object([
            "type": .string("object"),
            "required": .array([.string("query")]),
            "limit": .number(5),
            "enabled": .bool(true)
        ]))
    }

    @Test("Tool arguments bridge into MCP values without losing structure")
    func transportJSONToMCP() {
        let arguments: [String: JSONValue] = [
            "query": .string("needle"),
            "limit": .number(5),
            "nested": .object(["ok": .bool(true)])
        ]

        #expect(MCPValueBridge.arguments(from: arguments) == [
            "query": MCP.Value.string("needle"),
            "limit": MCP.Value.int(5),
            "nested": MCP.Value.object(["ok": .bool(true)])
        ])
    }
}
