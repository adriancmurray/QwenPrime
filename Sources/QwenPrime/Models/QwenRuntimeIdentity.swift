import Foundation

public struct QwenRuntimeIdentity: Decodable, Sendable, Equatable {
    public let runtimeId: String
    public let targetModelId: String
    public let draftModelId: String
    public let targetQuantizationBits: Int
    public let draftQuantizationBits: Int
    public let blockTokens: Int
    public let prefixCacheEnabled: Bool
    public let warmupComplete: Bool
    public let capabilities: [String]

    public init(
        runtimeId: String,
        targetModelId: String,
        draftModelId: String,
        targetQuantizationBits: Int,
        draftQuantizationBits: Int,
        blockTokens: Int,
        prefixCacheEnabled: Bool,
        warmupComplete: Bool,
        capabilities: [String] = []
    ) {
        self.runtimeId = runtimeId
        self.targetModelId = targetModelId
        self.draftModelId = draftModelId
        self.targetQuantizationBits = targetQuantizationBits
        self.draftQuantizationBits = draftQuantizationBits
        self.blockTokens = blockTokens
        self.prefixCacheEnabled = prefixCacheEnabled
        self.warmupComplete = warmupComplete
        self.capabilities = capabilities
    }

    enum CodingKeys: String, CodingKey {
        case runtimeId = "runtime_id"
        case targetModelId = "target_model_id"
        case draftModelId = "draft_model_id"
        case targetQuantizationBits = "target_quantization_bits"
        case draftQuantizationBits = "draft_quantization_bits"
        case blockTokens = "block_tokens"
        case prefixCacheEnabled = "prefix_cache_enabled"
        case warmupComplete = "warmup_complete"
        case capabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.runtimeId = try container.decode(String.self, forKey: .runtimeId)
        self.targetModelId = try container.decode(String.self, forKey: .targetModelId)
        self.draftModelId = try container.decode(String.self, forKey: .draftModelId)
        self.targetQuantizationBits = try container.decode(Int.self, forKey: .targetQuantizationBits)
        self.draftQuantizationBits = try container.decode(Int.self, forKey: .draftQuantizationBits)
        self.blockTokens = try container.decode(Int.self, forKey: .blockTokens)
        self.prefixCacheEnabled = try container.decode(Bool.self, forKey: .prefixCacheEnabled)
        self.warmupComplete = try container.decode(Bool.self, forKey: .warmupComplete)
        self.capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
    }

    public var supportsStructuredToolCalls: Bool {
        capabilities.contains("structured_tool_calls_v1")
    }

    public var isExpectedRuntime: Bool {
        runtimeId == "qwen38-native-mtp-v1"
            && targetModelId == "Qwen/Qwen3.8-27B"
            && draftModelId == "Qwen/Qwen3.8-27B#native-mtp"
            && targetQuantizationBits == 6
            && draftQuantizationBits == 6
            && blockTokens == 4
            && prefixCacheEnabled
            && warmupComplete
    }
}
