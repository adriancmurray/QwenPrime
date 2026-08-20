import Foundation
import Testing
@testable import QwenPrime

// MARK: - Agent Runtime Factory Seam

/// Wished dependency seam: factory closure creating a NativeAgentRuntime for a captured workspace URL.
public typealias AgentRuntimeFactory = @Sendable (URL) throws -> NativeAgentRuntime

// MARK: - Dedicated Race-Safe Mock Transport Registry & URLProtocol

/// Thread-safe registry routing mock HTTP requests by unique host per test instance to prevent cross-test interference.
public final class ChatIntegrationMockRegistry: @unchecked Sendable {
    public static let shared = ChatIntegrationMockRegistry()

    private let lock = NSLock()
    private var handlers: [String: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]

    public func register(host: String, handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        defer { lock.unlock() }
        handlers[host.lowercased()] = handler
    }

    public func unregister(host: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: host.lowercased())
    }

    public func handler(for host: String) -> (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[host.lowercased()]
    }
}

/// Dedicated race-safe URLProtocol dispatching exclusively to isolated test handlers registered in ChatIntegrationMockRegistry.
public final class ChatIntegrationURLProtocol: URLProtocol, @unchecked Sendable {
    public override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return ChatIntegrationMockRegistry.shared.handler(for: host) != nil
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        guard let host = request.url?.host,
              let handler = ChatIntegrationMockRegistry.shared.handler(for: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    public override func stopLoading() {}
}

/// Managed scope holding an isolated URLSession and baseURL mapped to a registered request handler.
public struct MockSSEScope: Sendable {
    public let baseURL: String
    public let session: URLSession
    public let host: String

    public init(handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        let uniqueHost = "mock-qwen-\(UUID().uuidString).local"
        self.host = uniqueHost
        self.baseURL = "http://\(uniqueHost)/v1"
        ChatIntegrationMockRegistry.shared.register(host: uniqueHost, handler: handler)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChatIntegrationURLProtocol.self]
        self.session = URLSession(configuration: config)
    }

    public func tearDown() {
        ChatIntegrationMockRegistry.shared.unregister(host: host)
    }
}

// MARK: - Safe HTTP Response Factory

public enum MockHTTPResponseFactory {
    public static func makeEventStreamResponse(
        url: URL,
        statusCode: Int = 200
    ) -> HTTPURLResponse? {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )
    }
}

// MARK: - SSE Formatting Helpers

public enum MockSSEFormatting {
    public static func formatSSEPayload(
        reasoningChunks: [String] = [],
        contentChunks: [String] = [],
        stats: GenerationStats? = nil
    ) -> Data {
        var lines: [String] = []

        for delta in reasoningChunks {
            let chunkDict: [String: Any] = [
                "choices": [
                    ["delta": ["reasoning_content": delta]]
                ]
            ]
            if let chunkData = try? JSONSerialization.data(withJSONObject: chunkDict),
               let jsonString = String(data: chunkData, encoding: .utf8) {
                lines.append("data: \(jsonString)\n\n")
            }
        }

        for delta in contentChunks {
            let chunkDict: [String: Any] = [
                "choices": [
                    ["delta": ["content": delta]]
                ]
            ]
            if let chunkData = try? JSONSerialization.data(withJSONObject: chunkDict),
               let jsonString = String(data: chunkData, encoding: .utf8) {
                lines.append("data: \(jsonString)\n\n")
            }
        }

        if let stats = stats {
            var usageDict: [String: Any] = [
                "prompt_tokens": stats.promptTokens,
                "completion_tokens": stats.completionTokens,
                "total_tokens": stats.totalTokens,
                "tokens_per_second": stats.tokensPerSecond
            ]
            if let val = stats.speculativeAcceptanceRate { usageDict["acceptance_ratio"] = val }
            if let val = stats.acceptedDraftTokens { usageDict["accepted_from_draft"] = val }
            if let val = stats.speculativeCycles { usageDict["cycles_completed"] = val }
            if let val = stats.prefillSeconds { usageDict["prefill_seconds"] = val }
            if let val = stats.prefillTokensPerSecond { usageDict["prefill_tokens_per_second"] = val }
            if let val = stats.prefillTokensComputed { usageDict["prefill_tokens_computed"] = val }
            if let val = stats.prefillTokensRestored { usageDict["prefill_tokens_restored"] = val }
            if let val = stats.prefixCacheHitTokens { usageDict["prefix_cache_hit_tokens"] = val }
            if let val = stats.reasoningTokens { usageDict["reasoning_tokens"] = val }
            if let val = stats.reasoningSeconds { usageDict["reasoning_seconds"] = val }

            let rootDict: [String: Any] = ["usage": usageDict]
            if let usageData = try? JSONSerialization.data(withJSONObject: rootDict),
               let jsonString = String(data: usageData, encoding: .utf8) {
                lines.append("data: \(jsonString)\n\n")
            }
        }

        lines.append("data: [DONE]\n\n")
        return lines.joined().data(using: .utf8) ?? Data()
    }
}

// MARK: - Condition-Based Bounded Wait

public enum AsyncCondition {
    public struct TimeoutError: Error, CustomStringConvertible, Sendable {
        public let message: String
        public var description: String { message }
    }

    /// Periodically polls condition until true or timeout is reached.
    @MainActor
    public static func wait(
        timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(10),
        description: String = "condition",
        _ condition: @MainActor @Sendable () async throws -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if try await condition() {
                return
            }
            try await Task.sleep(for: pollInterval)
        }
        throw TimeoutError(message: "Timed out after \(timeout) waiting for \(description)")
    }
}

// MARK: - Thread-Safe Test Execution Gate

/// Deterministic async gate for coordinating step-by-step concurrency in test suites without arbitrary sleeps.
public actor TestExecutionGate {
    private var isUnblocked = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func wait() async {
        if isUnblocked { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    public func unblock() {
        isUnblocked = true
        for continuation in continuations {
            continuation.resume()
        }
        continuations.removeAll()
    }

    public func reset() {
        isUnblocked = false
    }
}

// MARK: - Thread-Safe Lock-Backed Test Trackers

/// NSLock-backed typed tracker for recording factory invocations and captured workspace roots safely across concurrency boundaries.
public final class ThreadSafeFactoryTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount: Int = 0
    private var _capturedWorkspaceURLs: [URL] = []

    public init() {}

    public var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _callCount
    }

    public var capturedWorkspaceURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _capturedWorkspaceURLs
    }

    public func record(workspaceURL: URL) {
        lock.lock()
        defer { lock.unlock() }
        _callCount += 1
        _capturedWorkspaceURLs.append(workspaceURL)
    }
}

/// NSLock-backed typed tracker for counting turn invocations.
public final class ThreadSafeTurnCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _turnCount: Int = 0

    public init() {}

    public var turnCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _turnCount
    }

    public func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _turnCount += 1
        return _turnCount
    }
}

/// NSLock-backed typed capture for URL requests and bodies.
public final class ThreadSafeRequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _receivedRequests: [URLRequest] = []
    private var _receivedBodies: [Data] = []

    public init() {}

    public var receivedRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _receivedRequests
    }

    public var receivedBodies: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return _receivedBodies
    }

    public func record(request: URLRequest, body: Data?) {
        lock.lock()
        defer { lock.unlock() }
        _receivedRequests.append(request)
        if let body = body {
            _receivedBodies.append(body)
        }
    }
}

/// NSLock-backed typed tracker for runtime configuration and workspace snapshot capture.
public final class ThreadSafeRunSnapshotTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _capturedWorkspaceRoot: URL?
    private var _capturedRunConfig: AgentRunConfiguration?

    public init() {}

    public var capturedWorkspaceRoot: URL? {
        lock.lock()
        defer { lock.unlock() }
        return _capturedWorkspaceRoot
    }

    public var capturedRunConfig: AgentRunConfiguration? {
        lock.lock()
        defer { lock.unlock() }
        return _capturedRunConfig
    }

    public func record(workspaceRoot: URL) {
        lock.lock()
        defer { lock.unlock() }
        _capturedWorkspaceRoot = workspaceRoot
    }

    public func record(config: AgentRunConfiguration) {
        lock.lock()
        defer { lock.unlock() }
        _capturedRunConfig = config
    }
}

// MARK: - Temporary Storage Fixture

/// Creates an isolated temporary directory for StorageService instances during tests.
public struct TemporaryStorageFixture: Sendable {
    public let directoryURL: URL
    public let storage: StorageService

    public init() throws {
        let tempBase = FileManager.default.temporaryDirectory
        let uniqueDir = tempBase.appendingPathComponent("qwenprime-storage-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: uniqueDir, withIntermediateDirectories: true)
        self.directoryURL = uniqueDir
        self.storage = StorageService(directoryURL: uniqueDir)
    }

    public func tearDown() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

// MARK: - Test Support Helpers

public enum ChatIntegrationTestHelpers {
    public static func makeTestDefaults() throws -> (UserDefaults, String) {
        let suiteName = "QwenPrimeTests-ChatIntegration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    @MainActor
    static func withWorkspaceFixture(
        _ body: @MainActor (WorkspaceTestFixture) async throws -> Void
    ) async throws {
        let fixture = try WorkspaceTestFixture()
        defer { fixture.tearDown() }
        try await body(fixture)
    }
}
