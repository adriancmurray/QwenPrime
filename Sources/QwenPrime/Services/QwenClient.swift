import Foundation

private struct ToolMarkupStreamFilter {
    private static let openMarker = "<tool_call>"
    private static let closeMarker = "</tool_call>"

    private var pending = ""
    private var insideMarkup = false
    private var markupBuffer = ""

    mutating func push(_ text: String) -> String {
        var data = pending + text
        pending = ""
        var visible = ""

        while !data.isEmpty {
            if insideMarkup {
                let candidate = markupBuffer + data
                guard let closeRange = candidate.range(of: Self.closeMarker) else {
                    markupBuffer = candidate
                    break
                }
                data = String(candidate[closeRange.upperBound...])
                markupBuffer = ""
                insideMarkup = false
                continue
            }

            if let openRange = data.range(of: Self.openMarker) {
                visible += String(data[..<openRange.lowerBound])
                data = String(data[openRange.upperBound...])
                insideMarkup = true
                markupBuffer = Self.openMarker
                continue
            }

            let maximumSuffixLength = min(Self.openMarker.count, data.count)
            var heldLength = 0
            if maximumSuffixLength > 0 {
                for length in stride(from: maximumSuffixLength, through: 1, by: -1) {
                    if Self.openMarker.hasPrefix(data.suffix(length)) {
                        heldLength = length
                        break
                    }
                }
            }
            if heldLength > 0 {
                visible += String(data.dropLast(heldLength))
                pending = String(data.suffix(heldLength))
            } else {
                visible += data
            }
            break
        }

        return visible
    }

    mutating func finish() -> String {
        guard !insideMarkup else { return "" }
        defer { pending = "" }
        return pending
    }
}

/// Buffers raw SSE bytes until a complete UTF-8 line is available.
///
/// `URLSession.AsyncBytes.lines` can materialize replacement characters when a
/// multibyte scalar arrives across transport chunks. Keeping bytes intact until
/// the newline means JSON receives the exact server payload.
struct SSELineDecoder {
    private var bufferedBytes = Data()

    mutating func append(_ byte: UInt8) -> String? {
        guard byte == 0x0A else {
            bufferedBytes.append(byte)
            return nil
        }

        defer { bufferedBytes.removeAll(keepingCapacity: true) }
        let lineBytes = bufferedBytes.last == 0x0D
            ? bufferedBytes.dropLast()
            : bufferedBytes[...]
        return String(data: lineBytes, encoding: .utf8)
    }
}

public enum StreamEvent: Sendable, Equatable {
    case reasoningDelta(String)
    case contentDelta(String)
    case toolCall(ToolCall)
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
        baseURL: String = AppPreferences.defaultBaseURL,
        model: String = AppPreferences.defaultModel,
        temperature: Double = 0.1,
        systemPrompt: String? = nil,
        isThinkingEnabled: Bool = true,
        maxCompletionTokens: Int = 1024,
        maxReasoningTokens: Int = 96
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: URLError(.badURL))
            }
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
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }

        return executeStream(request: request, hasTools: false)
    }

    public func streamChat(
        messages: [ChatCompletionMessage],
        tools: [ToolDefinition]? = nil,
        baseURL: String = AppPreferences.defaultBaseURL,
        model: String = AppPreferences.defaultModel,
        temperature: Double = 0.1,
        systemPrompt: String? = nil,
        isThinkingEnabled: Bool = true,
        maxCompletionTokens: Int = 1024,
        maxReasoningTokens: Int = 96
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: URLError(.badURL))
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120.0

        var apiMessages: [[String: Any]] = []
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            apiMessages.append(["role": "system", "content": systemPrompt])
        }

        let encoder = JSONEncoder()
        for msg in messages {
            if msg.role == .system && systemPrompt != nil { continue }
            if let msgData = try? encoder.encode(msg),
               let msgDict = try? JSONSerialization.jsonObject(with: msgData) as? [String: Any] {
                apiMessages.append(msgDict)
            }
        }

        var requestBody: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": temperature,
            "stream": true,
            "thinking": ["type": isThinkingEnabled ? "enabled" : "disabled"],
            "max_completion_tokens": maxCompletionTokens,
            "max_reasoning_tokens": maxReasoningTokens
        ]

        if let tools = tools, !tools.isEmpty {
            if let toolsData = try? encoder.encode(tools),
               let toolsArray = try? JSONSerialization.jsonObject(with: toolsData) as? [[String: Any]] {
                requestBody["tools"] = toolsArray
            }
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }

        let hasTools = tools != nil && !(tools?.isEmpty ?? true)
        return executeStream(request: request, hasTools: hasTools)
    }

    private struct PartialToolCall {
        var id: String = ""
        var type: String = "function"
        var name: String = ""
        var arguments: String = ""
    }

    private func executeStream(
        request: URLRequest,
        hasTools: Bool
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let startTime = CFAbsoluteTimeGetCurrent()
                var firstTokenTime: CFAbsoluteTime?
                var completionTokenEstimator = StreamingTokenEstimator()
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

                var toolMarkupFilter = ToolMarkupStreamFilter()
                var partialToolCalls: [Int: PartialToolCall] = [:]
                var hasEmittedToolCalls = false

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

                    var sseLineDecoder = SSELineDecoder()
                    for try await byte in asyncBytes {
                        if Task.isCancelled { break }
                        guard let line = sseLineDecoder.append(byte) else {
                            continue
                        }
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
                           let firstChoice = choices.first {

                            var hasTokenData = false

                            if let delta = firstChoice["delta"] as? [String: Any] {
                                // 1. Reasoning / Thinking delta
                                if let reasoning = delta["reasoning_content"] as? String,
                                   completionTokenEstimator.append(reasoning) {
                                    if firstTokenTime == nil {
                                        firstTokenTime = CFAbsoluteTimeGetCurrent()
                                    }
                                    hasTokenData = true
                                    completionTokenCount = completionTokenEstimator
                                        .estimatedTokenCount
                                    continuation.yield(.reasoningDelta(reasoning))
                                }

                                // 2. Main content delta
                                if let content = delta["content"] as? String,
                                   completionTokenEstimator.append(content) {
                                    if firstTokenTime == nil {
                                        firstTokenTime = CFAbsoluteTimeGetCurrent()
                                    }
                                    hasTokenData = true
                                    completionTokenCount = completionTokenEstimator
                                        .estimatedTokenCount
                                    if hasTools {
                                        let visibleContent = toolMarkupFilter.push(content)
                                        if !visibleContent.isEmpty {
                                            continuation.yield(.contentDelta(visibleContent))
                                        }
                                    } else {
                                        continuation.yield(.contentDelta(content))
                                    }
                                }

                                // 3. Tool calls delta
                                if let toolCalls = delta["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                                    if firstTokenTime == nil {
                                        firstTokenTime = CFAbsoluteTimeGetCurrent()
                                    }
                                    hasTokenData = true

                                    for item in toolCalls {
                                        let index = item["index"] as? Int ?? 0
                                        if let id = item["id"] as? String {
                                            partialToolCalls[index, default: PartialToolCall()].id += id
                                        }
                                        if let type = item["type"] as? String {
                                            partialToolCalls[index, default: PartialToolCall()].type = type
                                        }
                                        if let fn = item["function"] as? [String: Any] {
                                            if let name = fn["name"] as? String {
                                                partialToolCalls[index, default: PartialToolCall()].name += name
                                            }
                                            if let args = fn["arguments"] as? String {
                                                partialToolCalls[index, default: PartialToolCall()].arguments += args
                                                if completionTokenEstimator.append(args) {
                                                    completionTokenCount = completionTokenEstimator
                                                        .estimatedTokenCount
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // 4. Finish reason handling
                            if let finishReason = firstChoice["finish_reason"] as? String {
                                if finishReason == "tool_calls" && !hasEmittedToolCalls {
                                    hasEmittedToolCalls = true
                                    for index in partialToolCalls.keys.sorted() {
                                        guard let partial = partialToolCalls[index] else { continue }
                                        let toolCall = ToolCall(
                                            id: partial.id,
                                            type: partial.type.isEmpty ? "function" : partial.type,
                                            function: ToolCall.FunctionCall(
                                                name: partial.name,
                                                arguments: partial.arguments
                                            )
                                        )
                                        continuation.yield(.toolCall(toolCall))
                                    }
                                    partialToolCalls.removeAll()
                                } else if finishReason == "stop" && hasTools {
                                    let trailingContent = toolMarkupFilter.finish()
                                    if !trailingContent.isEmpty {
                                        continuation.yield(.contentDelta(trailingContent))
                                    }
                                }
                            }

                            // 5. Emit Live Telemetry (Throttled to token boundaries)
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

                    if hasTools && !hasEmittedToolCalls {
                        let trailingContent = toolMarkupFilter.finish()
                        if !trailingContent.isEmpty {
                            continuation.yield(.contentDelta(trailingContent))
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
