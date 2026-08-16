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

    enum CodingKeys: String, CodingKey {
        case runtimeId = "runtime_id"
        case targetModelId = "target_model_id"
        case draftModelId = "draft_model_id"
        case targetQuantizationBits = "target_quantization_bits"
        case draftQuantizationBits = "draft_quantization_bits"
        case blockTokens = "block_tokens"
        case prefixCacheEnabled = "prefix_cache_enabled"
        case warmupComplete = "warmup_complete"
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
