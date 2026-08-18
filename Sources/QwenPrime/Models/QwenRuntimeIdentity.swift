import Foundation

public struct QuantizationIdentity: Decodable, Sendable, Equatable {
    public let scheme: String
    public let bits: [Int]
    public let defaultBits: Int
    public let groupSize: Int
    public let mode: String

    enum CodingKeys: String, CodingKey {
        case scheme, bits, mode
        case defaultBits = "default_bits"
        case groupSize = "group_size"
    }
}

public struct QwenRuntimeIdentity: Decodable, Sendable, Equatable {
    public let runtimeId: String
    public let targetModelId: String
    public let draftModelId: String
    public let targetQuantization: QuantizationIdentity
    public let draftQuantization: QuantizationIdentity
    public let blockTokens: Int
    public let prefixCacheEnabled: Bool
    public let warmupComplete: Bool
    public let capabilities: [String]

    public init(
        runtimeId: String,
        targetModelId: String,
        draftModelId: String,
        targetQuantization: QuantizationIdentity,
        draftQuantization: QuantizationIdentity,
        blockTokens: Int,
        prefixCacheEnabled: Bool,
        warmupComplete: Bool,
        capabilities: [String] = []
    ) {
        self.runtimeId = runtimeId
        self.targetModelId = targetModelId
        self.draftModelId = draftModelId
        self.targetQuantization = targetQuantization
        self.draftQuantization = draftQuantization
        self.blockTokens = blockTokens
        self.prefixCacheEnabled = prefixCacheEnabled
        self.warmupComplete = warmupComplete
        self.capabilities = capabilities
    }

    enum CodingKeys: String, CodingKey {
        case runtimeId = "runtime_id"
        case targetModelId = "target_model_id"
        case draftModelId = "draft_model_id"
        case targetQuantization = "target_quantization"
        case draftQuantization = "draft_quantization"
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
        self.targetQuantization = try container.decode(QuantizationIdentity.self, forKey: .targetQuantization)
        self.draftQuantization = try container.decode(QuantizationIdentity.self, forKey: .draftQuantization)
        self.blockTokens = try container.decode(Int.self, forKey: .blockTokens)
        self.prefixCacheEnabled = try container.decode(Bool.self, forKey: .prefixCacheEnabled)
        self.warmupComplete = try container.decode(Bool.self, forKey: .warmupComplete)
        self.capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
    }

    public var supportsStructuredToolCalls: Bool {
        capabilities.contains("structured_tool_calls_v1")
    }

    public var isExpectedRuntime: Bool {
        runtimeId == "qwen38-native-mtp-v2"
            && targetModelId == "Qwen/Qwen3.8-27B"
            && draftModelId == "Qwen/Qwen3.8-27B#native-mtp"
            && targetQuantization == QuantizationIdentity(
                scheme: "mixed",
                bits: [4, 8],
                defaultBits: 4,
                groupSize: 64,
                mode: "affine"
            )
            && draftQuantization == QuantizationIdentity(
                scheme: "uniform",
                bits: [6],
                defaultBits: 6,
                groupSize: 64,
                mode: "affine"
            )
            && blockTokens == 4
            && prefixCacheEnabled
            && warmupComplete
    }
}
