import Foundation

public struct QuantizationIdentity: Codable, Sendable, Equatable {
    public let scheme: String
    public let bits: [Int]
    public let defaultBits: Int
    public let groupSize: Int
    public let mode: String

    public init(
        scheme: String,
        bits: [Int],
        defaultBits: Int,
        groupSize: Int,
        mode: String
    ) {
        self.scheme = scheme
        self.bits = bits
        self.defaultBits = defaultBits
        self.groupSize = groupSize
        self.mode = mode
    }

    enum CodingKeys: String, CodingKey {
        case scheme, bits, mode
        case defaultBits = "default_bits"
        case groupSize = "group_size"
    }

    public var isHybridMixed: Bool {
        scheme == "mixed"
            && Set(bits) == Set([4, 8])
            && defaultBits == 4
            && groupSize == 64
            && mode == "affine"
    }

    public var isUniform6Bit: Bool {
        scheme == "uniform"
            && bits == [6]
            && defaultBits == 6
            && groupSize == 64
            && mode == "affine"
    }

    public var isCompatibleTargetQuantization: Bool {
        isHybridMixed || isUniform6Bit
    }

    public var isCompatibleDraftQuantization: Bool {
        isUniform6Bit
    }

    public var summary: String {
        if isHybridMixed {
            return "Mixed Q8/Q4"
        } else if isUniform6Bit {
            return "6-bit"
        } else if scheme == "mixed" {
            let sortedBits = bits.sorted(by: >).map(String.init).joined(separator: "/Q")
            return "Mixed Q\(sortedBits)"
        } else {
            return "\(defaultBits)-bit \(scheme)"
        }
    }
}

public struct RuntimeFeaturesIdentity: Decodable, Sendable, Equatable {
    public let verifyMode: String
    public let fusedMTP: Bool
    public let fp8KVCache: Bool

    enum CodingKeys: String, CodingKey {
        case verifyMode = "verify_mode"
        case fusedMTP = "fused_mtp"
        case fp8KVCache = "fp8_kv_cache"
    }
}

public struct QwenRuntimeIdentity: Decodable, Sendable, Equatable {
    public let runtimeId: String
    public let targetModelId: String
    public let draftModelId: String
    public let targetPath: String?
    public let draftPath: String?
    public let targetQuantization: QuantizationIdentity
    public let draftQuantization: QuantizationIdentity
    public let blockTokens: Int
    public let prefixCacheEnabled: Bool
    public let warmupComplete: Bool
    public let capabilities: [String]
    public let runtimeFeatures: RuntimeFeaturesIdentity?

    public init(
        runtimeId: String,
        targetModelId: String,
        draftModelId: String,
        targetPath: String? = nil,
        draftPath: String? = nil,
        targetQuantization: QuantizationIdentity,
        draftQuantization: QuantizationIdentity,
        blockTokens: Int,
        prefixCacheEnabled: Bool,
        warmupComplete: Bool,
        capabilities: [String] = [],
        runtimeFeatures: RuntimeFeaturesIdentity? = nil
    ) {
        self.runtimeId = runtimeId
        self.targetModelId = targetModelId
        self.draftModelId = draftModelId
        self.targetPath = targetPath
        self.draftPath = draftPath
        self.targetQuantization = targetQuantization
        self.draftQuantization = draftQuantization
        self.blockTokens = blockTokens
        self.prefixCacheEnabled = prefixCacheEnabled
        self.warmupComplete = warmupComplete
        self.capabilities = capabilities
        self.runtimeFeatures = runtimeFeatures
    }

    enum CodingKeys: String, CodingKey {
        case runtimeId = "runtime_id"
        case targetModelId = "target_model_id"
        case draftModelId = "draft_model_id"
        case targetPath = "target_path"
        case draftPath = "draft_path"
        case targetQuantization = "target_quantization"
        case draftQuantization = "draft_quantization"
        case blockTokens = "block_tokens"
        case prefixCacheEnabled = "prefix_cache_enabled"
        case warmupComplete = "warmup_complete"
        case capabilities
        case runtimeFeatures = "runtime_features"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.runtimeId = try container.decode(String.self, forKey: .runtimeId)
        self.targetModelId = try container.decode(String.self, forKey: .targetModelId)
        self.draftModelId = try container.decode(String.self, forKey: .draftModelId)
        self.targetPath = try container.decodeIfPresent(String.self, forKey: .targetPath)
        self.draftPath = try container.decodeIfPresent(String.self, forKey: .draftPath)
        self.targetQuantization = try container.decode(QuantizationIdentity.self, forKey: .targetQuantization)
        self.draftQuantization = try container.decode(QuantizationIdentity.self, forKey: .draftQuantization)
        self.blockTokens = try container.decode(Int.self, forKey: .blockTokens)
        self.prefixCacheEnabled = try container.decode(Bool.self, forKey: .prefixCacheEnabled)
        self.warmupComplete = try container.decode(Bool.self, forKey: .warmupComplete)
        self.capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        self.runtimeFeatures = try container.decodeIfPresent(
            RuntimeFeaturesIdentity.self,
            forKey: .runtimeFeatures
        )
    }

    public var supportsStructuredToolCalls: Bool {
        capabilities.contains("structured_tool_calls_v1")
    }

    public var isExpectedRuntime: Bool {
        runtimeId == "qwen38-native-mtp-v2"
            && targetModelId == "Qwen/Qwen3.8-27B"
            && draftModelId == "Qwen/Qwen3.8-27B#native-mtp"
            && targetQuantization.isCompatibleTargetQuantization
            && draftQuantization.isCompatibleDraftQuantization
            && blockTokens == 4
            && prefixCacheEnabled
            && warmupComplete
    }

    public var quantizationSummary: String {
        if targetQuantization.isHybridMixed && draftQuantization.isUniform6Bit {
            return "Hybrid Q8/Q4 + 6-bit MTP"
        } else if targetQuantization.isUniform6Bit && draftQuantization.isUniform6Bit {
            return "Uniform 6-bit + 6-bit MTP"
        } else {
            return "\(targetQuantization.summary) + \(draftQuantization.summary) MTP"
        }
    }

    public var displaySummary: String {
        "Qwen 3.8 27B (\(quantizationSummary))"
    }

    public var featureSummary: String {
        guard let runtimeFeatures else { return "Adaptive verification" }
        var features = [runtimeFeatures.verifyMode.capitalized]
        if runtimeFeatures.fusedMTP { features.append("Fused MTP") }
        if runtimeFeatures.fp8KVCache { features.append("FP8 KV") }
        return features.joined(separator: " · ")
    }

    public func matches(_ profile: RuntimeModelProfile) -> Bool {
        guard let targetPath, let draftPath else { return false }
        return Self.normalizedModelPath(targetPath)
            == Self.normalizedModelPath(profile.targetModelPath)
            && Self.normalizedModelPath(draftPath)
                == Self.normalizedModelPath(profile.draftModelPath)
    }

    private static func normalizedModelPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}
