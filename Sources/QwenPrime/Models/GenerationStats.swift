import Foundation

public struct GenerationStats: Codable, Sendable, Equatable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int { promptTokens + completionTokens }
    public var tokensPerSecond: Double
    public var latencySeconds: Double
    public var timeToFirstTokenSeconds: Double

    public init(
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        tokensPerSecond: Double = 0.0,
        latencySeconds: Double = 0.0,
        timeToFirstTokenSeconds: Double = 0.0
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.tokensPerSecond = tokensPerSecond
        self.latencySeconds = latencySeconds
        self.timeToFirstTokenSeconds = timeToFirstTokenSeconds
    }
}
