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

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func streamChat(
        messages: [ChatMessage],
        baseURL: String = "http://127.0.0.1:8000/v1",
        model: String = "qwen3.8-27b",
        temperature: Double = 0.1,
        systemPrompt: String? = nil
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
                    let msgDict: [String: Any] = [
                        "role": msg.role.rawValue,
                        "content": msg.content
                    ]
                    apiMessages.append(msgDict)
                }

                let requestBody: [String: Any] = [
                    "model": model,
                    "messages": apiMessages,
                    "temperature": temperature,
                    "stream": true
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

                            if firstTokenTime == nil {
                                firstTokenTime = CFAbsoluteTimeGetCurrent()
                            }

                            // 1. Reasoning / Thinking delta
                            if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
                                completionTokenCount += max(1, reasoning.count / 4)
                                continuation.yield(.reasoningDelta(reasoning))
                            }

                            // 2. Main content delta
                            if let content = delta["content"] as? String, !content.isEmpty {
                                completionTokenCount += max(1, content.count / 4)
                                continuation.yield(.contentDelta(content))
                            }
                        }

                        if let usage = json["usage"] as? [String: Any] {
                            if let p = usage["prompt_tokens"] as? Int { promptTokenCount = p }
                            if let c = usage["completion_tokens"] as? Int { completionTokenCount = c }
                        }
                    }

                    let endTime = CFAbsoluteTimeGetCurrent()
                    let totalElapsed = max(0.001, endTime - startTime)
                    let ttft = firstTokenTime.map { $0 - startTime } ?? totalElapsed
                    let tokPerSec = Double(completionTokenCount) / totalElapsed

                    let stats = GenerationStats(
                        promptTokens: promptTokenCount,
                        completionTokens: completionTokenCount,
                        tokensPerSecond: round(tokPerSec * 10) / 10.0,
                        latencySeconds: round(totalElapsed * 100) / 100.0,
                        timeToFirstTokenSeconds: round(ttft * 100) / 100.0
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
