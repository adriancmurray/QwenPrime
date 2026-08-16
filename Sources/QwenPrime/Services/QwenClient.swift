import Foundation

public enum StreamEvent: Sendable, Equatable {
    case reasoningDelta(String)
    case contentDelta(String)
    case usage(GenerationStats)
    case finished
}

public actor QwenClient {
    public static let shared = QwenClient()

    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 120.0
            config.timeoutIntervalForResource = 3600.0
            config.waitsForConnectivity = false
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    public func streamChat(
        messages: [ChatMessage],
        baseURL: String = "http://127.0.0.1:8000/v1",
        model: String = "qwen3.8-27b",
        temperature: Double = 0.1,
        systemPrompt: String? = nil,
        isThinkingEnabled: Bool = true,
        maxCompletionTokens: Int = 1024,
        maxReasoningTokens: Int = 96
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard let url = URL(string: "\(baseURL)/chat/completions") else {
                    continuation.finish(throwing: URLError(.badURL))
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 120.0

                // Build message payload
                var apiMessages: [[String: Any]] = []
                if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
                    apiMessages.append(["role": "system", "content": systemPrompt])
                }

                for msg in messages {
                    if msg.role == .system { continue }
                    var msgDict: [String: Any] = [
                        "role": msg.role.rawValue,
                        "content": msg.content
                    ]
                    if msg.role == .assistant,
                       let thinkingContent = msg.thinkingContent,
                       !thinkingContent.isEmpty {
                        msgDict["reasoning_content"] = thinkingContent
                    }
                    apiMessages.append(msgDict)
                }

                let requestBody: [String: Any] = [
                    "model": model,
                    "messages": apiMessages,
                    "temperature": temperature,
                    "stream": true,
                    "thinking": ["type": isThinkingEnabled ? "enabled" : "disabled"],
                    "max_completion_tokens": maxCompletionTokens,
                    "max_reasoning_tokens": maxReasoningTokens
                ]

                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                let startTime = CFAbsoluteTimeGetCurrent()
                var firstTokenTime: CFAbsoluteTime?
                var completionTokenCount = 0
                var promptTokenCount = 0
                var serverTokensPerSec: Double?
                var speculativeAcceptanceRate: Double?
                var acceptedDraftTokens: Int?
                var speculativeCycles: Int?
                var prefillSeconds: Double?
                var prefillTokensPerSecond: Double?
                var prefillTokensComputed: Int?
                var prefillTokensRestored: Int?
                var prefixCacheHitTokens: Int?
                var reasoningTokens: Int?
                var reasoningSeconds: Double?

                do {
                    let (asyncBytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                        continuation.finish(throwing: NSError(
                            domain: "QwenClient",
                            code: status,
                            userInfo: [NSLocalizedDescriptionKey: "Server returned error status \(status)"]
                        ))
                        return
                    }

                    for try await line in asyncBytes.lines {
                        if Task.isCancelled { break }
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data:") else { continue }

                        let dataStr = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if dataStr == "[DONE]" {
                            break
                        }

                        guard let data = dataStr.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            continue
                        }

                        if let choices = json["choices"] as? [[String: Any]],
                           let firstChoice = choices.first,
                           let delta = firstChoice["delta"] as? [String: Any] {

                            var hasTokenData = false

                            // 1. Reasoning / Thinking delta
                            if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
                                if firstTokenTime == nil {
                                    firstTokenTime = CFAbsoluteTimeGetCurrent()
                                }
                                hasTokenData = true
                                completionTokenCount += max(1, reasoning.count / 4)
                                continuation.yield(.reasoningDelta(reasoning))
                            }

                            // 2. Main content delta
                            if let content = delta["content"] as? String, !content.isEmpty {
                                if firstTokenTime == nil {
                                    firstTokenTime = CFAbsoluteTimeGetCurrent()
                                }
                                hasTokenData = true
                                completionTokenCount += max(1, content.count / 4)
                                continuation.yield(.contentDelta(content))
                            }

                            // 3. Emit Live Telemetry (Throttled to token boundaries)
                            if hasTokenData, let ft = firstTokenTime {
                                let currentElapsed = max(0.01, CFAbsoluteTimeGetCurrent() - ft)
                                let currentTps = Double(completionTokenCount) / currentElapsed
                                let liveStats = GenerationStats(
                                    promptTokens: promptTokenCount,
                                    completionTokens: completionTokenCount,
                                    tokensPerSecond: round(currentTps * 10) / 10.0,
                                    latencySeconds: round((CFAbsoluteTimeGetCurrent() - startTime) * 100) / 100.0,
                                    timeToFirstTokenSeconds: round((ft - startTime) * 100) / 100.0,
                                    isThroughputEstimated: true
                                )
                                continuation.yield(.usage(liveStats))
                            }
                        }

                        if let usage = json["usage"] as? [String: Any] {
                            if let p = usage["prompt_tokens"] as? Int { promptTokenCount = p }
                            if let c = usage["completion_tokens"] as? Int { completionTokenCount = c }
                            if let tps = usage["tokens_per_second"] as? Double { serverTokensPerSec = tps }
                            if let acceptance = usage["acceptance_ratio"] as? Double {
                                speculativeAcceptanceRate = acceptance
                            }
                            if let accepted = usage["accepted_from_draft"] as? Int {
                                acceptedDraftTokens = accepted
                            }
                            if let cycles = usage["cycles_completed"] as? Int {
                                speculativeCycles = cycles
                            }
                            if let value = usage["prefill_seconds"] as? Double {
                                prefillSeconds = value
                            }
                            if let value = usage["prefill_tokens_per_second"] as? Double {
                                prefillTokensPerSecond = value
                            }
                            if let value = usage["prefill_tokens_computed"] as? Int {
                                prefillTokensComputed = value
                            }
                            if let value = usage["prefill_tokens_restored"] as? Int {
                                prefillTokensRestored = value
                            }
                            if let value = usage["prefix_cache_hit_tokens"] as? Int {
                                prefixCacheHitTokens = value
                            }
                            if let value = usage["reasoning_tokens"] as? Int {
                                reasoningTokens = value
                            }
                            if let value = usage["reasoning_seconds"] as? Double {
                                reasoningSeconds = value
                            }
                        }
                    }

                    let endTime = CFAbsoluteTimeGetCurrent()
                    let totalElapsed = max(0.001, endTime - startTime)
                    let ttft = firstTokenTime.map { $0 - startTime } ?? totalElapsed
                    let effectiveTps = serverTokensPerSec ?? (Double(completionTokenCount) / max(0.001, totalElapsed - ttft))

                    let stats = GenerationStats(
                        promptTokens: promptTokenCount,
                        completionTokens: completionTokenCount,
                        tokensPerSecond: round(effectiveTps * 10) / 10.0,
                        latencySeconds: round(totalElapsed * 100) / 100.0,
                        timeToFirstTokenSeconds: round(ttft * 100) / 100.0,
                        speculativeAcceptanceRate: speculativeAcceptanceRate,
                        acceptedDraftTokens: acceptedDraftTokens,
                        speculativeCycles: speculativeCycles,
                        prefillSeconds: prefillSeconds,
                        prefillTokensPerSecond: prefillTokensPerSecond,
                        prefillTokensComputed: prefillTokensComputed,
                        prefillTokensRestored: prefillTokensRestored,
                        prefixCacheHitTokens: prefixCacheHitTokens,
                        reasoningTokens: reasoningTokens,
                        reasoningSeconds: reasoningSeconds,
                        isThroughputEstimated: false
                    )

                    continuation.yield(.usage(stats))
                    continuation.yield(.finished)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
