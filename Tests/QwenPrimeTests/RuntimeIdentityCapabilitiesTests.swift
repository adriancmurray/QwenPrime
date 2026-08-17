import Testing
import Foundation
@testable import QwenPrime

@Suite("Runtime Identity Capabilities Contract Tests")
struct RuntimeIdentityCapabilitiesTests {

    @Test("QwenRuntimeIdentity decodes additive capabilities array and reports supportsStructuredToolCalls")
    func testRuntimeIdentityCapabilitiesDecoding() throws {
        // 1. Tool-capable runtime with exact versioned capability string structured_tool_calls_v1
        let capableJSON = Data("""
        {
            "runtime_id": "qwen38-native-mtp-v1",
            "target_model_id": "Qwen/Qwen3.8-27B",
            "draft_model_id": "Qwen/Qwen3.8-27B#native-mtp",
            "target_quantization_bits": 6,
            "draft_quantization_bits": 6,
            "block_tokens": 4,
            "prefix_cache_enabled": true,
            "warmup_complete": true,
            "capabilities": ["structured_tool_calls_v1"]
        }
        """.utf8)

        let capableIdentity = try JSONDecoder().decode(QwenRuntimeIdentity.self, from: capableJSON)
        #expect(capableIdentity.capabilities == ["structured_tool_calls_v1"])
        #expect(capableIdentity.supportsStructuredToolCalls == true)

        // 2. Legacy v1.1 runtime omitting capabilities array - modeled as nonoptional empty collection
        let legacyJSON = Data("""
        {
            "runtime_id": "qwen38-native-mtp-v1",
            "target_model_id": "Qwen/Qwen3.8-27B",
            "draft_model_id": "Qwen/Qwen3.8-27B#native-mtp",
            "target_quantization_bits": 6,
            "draft_quantization_bits": 6,
            "block_tokens": 4,
            "prefix_cache_enabled": true,
            "warmup_complete": true
        }
        """.utf8)

        let legacyIdentity = try JSONDecoder().decode(QwenRuntimeIdentity.self, from: legacyJSON)
        #expect(legacyIdentity.capabilities.isEmpty)
        #expect(legacyIdentity.capabilities == [])
        #expect(legacyIdentity.supportsStructuredToolCalls == false)

        // 3. Runtime with unrelated capabilities
        let otherCapabilitiesJSON = Data("""
        {
            "runtime_id": "qwen38-native-mtp-v1",
            "target_model_id": "Qwen/Qwen3.8-27B",
            "draft_model_id": "Qwen/Qwen3.8-27B#native-mtp",
            "target_quantization_bits": 6,
            "draft_quantization_bits": 6,
            "block_tokens": 4,
            "prefix_cache_enabled": true,
            "warmup_complete": true,
            "capabilities": ["unrelated_feature"]
        }
        """.utf8)

        let otherIdentity = try JSONDecoder().decode(QwenRuntimeIdentity.self, from: otherCapabilitiesJSON)
        #expect(otherIdentity.capabilities == ["unrelated_feature"])
        #expect(otherIdentity.supportsStructuredToolCalls == false)
    }
}
