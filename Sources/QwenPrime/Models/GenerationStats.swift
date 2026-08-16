import Foundation

public struct GenerationStats: Codable, Sendable, Equatable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int { promptTokens + completionTokens }
    public var tokensPerSecond: Double
    public var latencySeconds: Double
    public var timeToFirstTokenSeconds: Double
    public var speculativeAcceptanceRate: Double?
    public var acceptedDraftTokens: Int?
    public var speculativeCycles: Int?
    public var prefillSeconds: Double?
    public var prefillTokensPerSecond: Double?
    public var prefillTokensComputed: Int?
    public var prefillTokensRestored: Int?
    public var prefixCacheHitTokens: Int?
    public var reasoningTokens: Int?
    public var reasoningSeconds: Double?
    public var isThroughputEstimated: Bool?

    public init(
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        tokensPerSecond: Double = 0.0,
        latencySeconds: Double = 0.0,
        timeToFirstTokenSeconds: Double = 0.0,
        speculativeAcceptanceRate: Double? = nil,
        acceptedDraftTokens: Int? = nil,
        speculativeCycles: Int? = nil,
        prefillSeconds: Double? = nil,
        prefillTokensPerSecond: Double? = nil,
        prefillTokensComputed: Int? = nil,
        prefillTokensRestored: Int? = nil,
        prefixCacheHitTokens: Int? = nil,
        reasoningTokens: Int? = nil,
        reasoningSeconds: Double? = nil,
        isThroughputEstimated: Bool? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.tokensPerSecond = tokensPerSecond
        self.latencySeconds = latencySeconds
        self.timeToFirstTokenSeconds = timeToFirstTokenSeconds
        self.speculativeAcceptanceRate = speculativeAcceptanceRate
        self.acceptedDraftTokens = acceptedDraftTokens
        self.speculativeCycles = speculativeCycles
        self.prefillSeconds = prefillSeconds
        self.prefillTokensPerSecond = prefillTokensPerSecond
        self.prefillTokensComputed = prefillTokensComputed
        self.prefillTokensRestored = prefillTokensRestored
        self.prefixCacheHitTokens = prefixCacheHitTokens
        self.reasoningTokens = reasoningTokens
        self.reasoningSeconds = reasoningSeconds
        self.isThroughputEstimated = isThroughputEstimated
    }
}
