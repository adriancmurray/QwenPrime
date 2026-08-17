import Testing
import Foundation
@testable import QwenPrime

// MARK: - Dedicated Race-Safe Mock Transport Registry & URLProtocol

/// Thread-safe registry routing mock health HTTP requests by unique host per test instance to prevent cross-test interference.
public final class HealthMockTransportRegistry: @unchecked Sendable {
    public static let shared = HealthMockTransportRegistry()

    private let lock = NSLock()
    private var handlers: [String: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]

    public func register(host: String, handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        defer { lock.unlock() }
        handlers[host] = handler
    }

    public func unregister(host: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: host)
    }

    public func handler(for host: String) -> (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[host]
    }
}

/// Dedicated race-safe URLProtocol dispatching exclusively to isolated test handlers registered in HealthMockTransportRegistry.
public final class HealthMockURLProtocol: URLProtocol, @unchecked Sendable {
    public override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return HealthMockTransportRegistry.shared.handler(for: host) != nil
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        guard let host = request.url?.host,
              let handler = HealthMockTransportRegistry.shared.handler(for: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let request = request
        DispatchQueue.global().async { [self] in
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    public override func stopLoading() {}
}

/// Managed scope holding an isolated URLSession and baseURL mapped to a registered request handler.
public struct MockHealthServerScope: Sendable {
    public let baseURL: String
    public let session: URLSession
    public let host: String

    public init(handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        let uniqueHost = "mock-health-\(UUID().uuidString).local"
        self.host = uniqueHost
        self.baseURL = "http://\(uniqueHost)/v1"
        HealthMockTransportRegistry.shared.register(host: uniqueHost, handler: handler)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HealthMockURLProtocol.self]
        self.session = URLSession(configuration: config)
    }

    public func updateHandler(_ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        HealthMockTransportRegistry.shared.register(host: host, handler: handler)
    }

    public func tearDown() {
        HealthMockTransportRegistry.shared.unregister(host: host)
    }
}

// MARK: - Mock Health Payloads and Response Helpers

public enum MockHealthFixtures {
    public enum FixtureError: Error {
        case responseCreationFailed
    }

    public static func makeResponse(
        url: URL,
        statusCode: Int = 200,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) throws -> HTTPURLResponse {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            throw FixtureError.responseCreationFailed
        }
        return response
    }

    public static let capableIdentityJSON = Data("""
    {
        "runtime_id": "qwen38-native-mtp-v1",
        "target_model_id": "Qwen/Qwen3.8-27B",
        "draft_model_id": "Qwen/Qwen3.8-27B#native-mtp",
        "target_quantization_bits": 6,
        "draft_quantization_bits": 6,
        "block_tokens": 4,
        "prefix_cache_enabled": true,
        "warmup_complete": true,
        "capabilities": ["structured_tool_calls_v1"]
    }
    """.utf8)

    public static let legacyOmittedCapabilitiesJSON = Data("""
    {
        "runtime_id": "qwen38-native-mtp-v1",
        "target_model_id": "Qwen/Qwen3.8-27B",
        "draft_model_id": "Qwen/Qwen3.8-27B#native-mtp",
        "target_quantization_bits": 6,
        "draft_quantization_bits": 6,
        "block_tokens": 4,
        "prefix_cache_enabled": true,
        "warmup_complete": true
    }
    """.utf8)

    public static let legacyEmptyCapabilitiesJSON = Data("""
    {
        "runtime_id": "qwen38-native-mtp-v1",
        "target_model_id": "Qwen/Qwen3.8-27B",
        "draft_model_id": "Qwen/Qwen3.8-27B#native-mtp",
        "target_quantization_bits": 6,
        "draft_quantization_bits": 6,
        "block_tokens": 4,
        "prefix_cache_enabled": true,
        "warmup_complete": true,
        "capabilities": []
    }
    """.utf8)

    public static let unexpectedRuntimeJSON = Data("""
    {
        "runtime_id": "qwen38-unsupported-v2",
        "target_model_id": "Qwen/Qwen3.8-27B",
        "draft_model_id": "Qwen/Qwen3.8-27B#native-mtp",
        "target_quantization_bits": 6,
        "draft_quantization_bits": 6,
        "block_tokens": 4,
        "prefix_cache_enabled": true,
        "warmup_complete": true,
        "capabilities": ["structured_tool_calls_v1"]
    }
    """.utf8)

    public static let malformedJSON = Data("{\"runtime_id\": [invalid json".utf8)
}

// MARK: - ServerHealthService Tests

@Suite("ServerHealthService Runtime Capability Integration Tests")
struct ServerHealthServiceRuntimeCapabilityTests {

    @Test("Capable /v1/engine identity with capabilities=[structured_tool_calls_v1] yields connected and stored supports=true")
    func testCapableRuntimeHealthCheckStoresIdentityWithStructuredToolCallsSupport() async throws {
        let scope = MockHealthServerScope { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            guard url.path == "/v1/engine" else {
                return (try MockHealthFixtures.makeResponse(url: url, statusCode: 404), Data())
            }
            return (try MockHealthFixtures.makeResponse(url: url, statusCode: 200), MockHealthFixtures.capableIdentityJSON)
        }
        defer { scope.tearDown() }

        let healthService = ServerHealthService(session: scope.session)
        let status = await healthService.checkHealth(baseURL: scope.baseURL)

        #expect(status.isConnected == true)
        let identity = await healthService.currentIdentity()
        let unwrappedIdentity = try #require(identity)
        #expect(unwrappedIdentity.capabilities == ["structured_tool_calls_v1"])
        #expect(unwrappedIdentity.supportsStructuredToolCalls == true)
        #expect(unwrappedIdentity.isExpectedRuntime == true)
        #expect(await healthService.currentIdentity(for: scope.baseURL) != nil)
        #expect(await healthService.currentIdentity(for: "http://unverified-endpoint.local/v1") == nil)
    }

    @Test("Legacy identity without capabilities still yields connected expected runtime but stored supports=false")
    func testLegacyRuntimeHealthCheckStoresIdentityWithStructuredToolCallsDisabled() async throws {
        let scope = MockHealthServerScope { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            guard url.path == "/v1/engine" else {
                return (try MockHealthFixtures.makeResponse(url: url, statusCode: 404), Data())
            }
            return (try MockHealthFixtures.makeResponse(url: url, statusCode: 200), MockHealthFixtures.legacyOmittedCapabilitiesJSON)
        }
        defer { scope.tearDown() }

        let healthService = ServerHealthService(session: scope.session)
        let status = await healthService.checkHealth(baseURL: scope.baseURL)

        #expect(status.isConnected == true)
        let identity = await healthService.currentIdentity()
        let unwrappedIdentity = try #require(identity)
        #expect(unwrappedIdentity.capabilities.isEmpty)
        #expect(unwrappedIdentity.supportsStructuredToolCalls == false)
        #expect(unwrappedIdentity.isExpectedRuntime == true)
    }

    @Test("Legacy identity with explicit empty capabilities array yields connected but stored supports=false")
    func testLegacyEmptyCapabilitiesHealthCheckStoresIdentityWithStructuredToolCallsDisabled() async throws {
        let scope = MockHealthServerScope { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            guard url.path == "/v1/engine" else {
                return (try MockHealthFixtures.makeResponse(url: url, statusCode: 404), Data())
            }
            return (try MockHealthFixtures.makeResponse(url: url, statusCode: 200), MockHealthFixtures.legacyEmptyCapabilitiesJSON)
        }
        defer { scope.tearDown() }

        let healthService = ServerHealthService(session: scope.session)
        let status = await healthService.checkHealth(baseURL: scope.baseURL)

        #expect(status.isConnected == true)
        let identity = await healthService.currentIdentity()
        let unwrappedIdentity = try #require(identity)
        #expect(unwrappedIdentity.capabilities == [])
        #expect(unwrappedIdentity.supportsStructuredToolCalls == false)
        #expect(unwrappedIdentity.isExpectedRuntime == true)
    }

    @Test("HTTP error status codes clear stored identity and yield disconnected")
    func testHTTPErrorStatusClearsStoredIdentity() async throws {
        let scope = MockHealthServerScope { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            return (try MockHealthFixtures.makeResponse(url: url, statusCode: 500), Data("Internal Server Error".utf8))
        }
        defer { scope.tearDown() }

        let healthService = ServerHealthService(session: scope.session)
        let status = await healthService.checkHealth(baseURL: scope.baseURL)

        #expect(status.isConnected == false)
        let identity = await healthService.currentIdentity()
        #expect(identity == nil)
    }

    @Test("Network and transport failures clear stored identity and yield disconnected")
    func testNetworkFailureClearsStoredIdentity() async throws {
        let scope = MockHealthServerScope { _ in
            throw URLError(.cannotConnectToHost)
        }
        defer { scope.tearDown() }

        let healthService = ServerHealthService(session: scope.session)
        let status = await healthService.checkHealth(baseURL: scope.baseURL)

        #expect(status.isConnected == false)
        let identity = await healthService.currentIdentity()
        #expect(identity == nil)
    }

    @Test("Decode failures on malformed payload clear stored identity and yield disconnected")
    func testDecodeFailureClearsStoredIdentity() async throws {
        let scope = MockHealthServerScope { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            return (try MockHealthFixtures.makeResponse(url: url, statusCode: 200), MockHealthFixtures.malformedJSON)
        }
        defer { scope.tearDown() }

        let healthService = ServerHealthService(session: scope.session)
        let status = await healthService.checkHealth(baseURL: scope.baseURL)

        #expect(status.isConnected == false)
        let identity = await healthService.currentIdentity()
        #expect(identity == nil)
    }

    @Test("Unexpected runtime identity clears stored identity and yields disconnected")
    func testUnexpectedRuntimeIdentityClearsStoredIdentity() async throws {
        let scope = MockHealthServerScope { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            return (try MockHealthFixtures.makeResponse(url: url, statusCode: 200), MockHealthFixtures.unexpectedRuntimeJSON)
        }
        defer { scope.tearDown() }

        let healthService = ServerHealthService(session: scope.session)
        let status = await healthService.checkHealth(baseURL: scope.baseURL)

        #expect(status.isConnected == false)
        let identity = await healthService.currentIdentity()
        #expect(identity == nil)
    }

    @Test("Subsequent failure after successful health check clears previously verified identity")
    func testSubsequentFailureClearsPreviouslyVerifiedIdentity() async throws {
        let scope = MockHealthServerScope { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            return (try MockHealthFixtures.makeResponse(url: url, statusCode: 200), MockHealthFixtures.capableIdentityJSON)
        }
        defer { scope.tearDown() }

        let healthService = ServerHealthService(session: scope.session)

        // 1. Initial health check succeeds and stores verified capable identity
        let initialStatus = await healthService.checkHealth(baseURL: scope.baseURL)
        #expect(initialStatus.isConnected == true)
        let initialIdentity = await healthService.currentIdentity()
        #expect(initialIdentity?.supportsStructuredToolCalls == true)

        // 2. Server transitions to failing/disconnected
        scope.updateHandler { _ in
            throw URLError(.networkConnectionLost)
        }

        let failedStatus = await healthService.checkHealth(baseURL: scope.baseURL)
        #expect(failedStatus.isConnected == false)
        let clearedIdentity = await healthService.currentIdentity()
        #expect(clearedIdentity == nil)
    }
}

// MARK: - AppState Integration Tests

@Suite("AppState Runtime Capability Health Integration Tests")
struct AppStateRuntimeCapabilityHealthIntegrationTests {

    private func makeTestEnvironment() throws -> (UserDefaults, String, URL, StorageService, RuntimeConfigurationService) {
        let suiteName = "QwenPrimeTests-HealthCapability-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QwenPrimeTests-Health-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storage = StorageService(directoryURL: tempDir.appendingPathComponent("storage", isDirectory: true))
        let configService = RuntimeConfigurationService(configurationURL: tempDir.appendingPathComponent("config.json"))
        return (defaults, suiteName, tempDir, storage, configService)
    }

    @Test("checkServerHealth against capable identity sets runtimeSupportsStructuredToolCalls true")
    @MainActor
    func testCheckServerHealthWithCapableIdentitySetsCapabilityTrue() async throws {
        let (defaults, suiteName, tempDir, storage, configService) = try makeTestEnvironment()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let scope = MockHealthServerScope { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            return (try MockHealthFixtures.makeResponse(url: url, statusCode: 200), MockHealthFixtures.capableIdentityJSON)
        }
        defer { scope.tearDown() }

        let healthService = ServerHealthService(session: scope.session)
        let appState = AppState(
            baseURL: scope.baseURL,
            startServices: false,
            healthService: healthService,
            runtimeConfigurationService: configService,
            userDefaults: defaults,
            storage: storage
        )

        #expect(appState.runtimeSupportsStructuredToolCalls == false)
        await appState.checkServerHealth()

        #expect(appState.serverStatus.isConnected == true)
        #expect(appState.runtimeSupportsStructuredToolCalls == true)
    }

    @Test("checkServerHealth against legacy identity sets runtimeSupportsStructuredToolCalls false while connected")
    @MainActor
    func testCheckServerHealthWithLegacyIdentitySetsCapabilityFalse() async throws {
        let (defaults, suiteName, tempDir, storage, configService) = try makeTestEnvironment()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let scope = MockHealthServerScope { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            return (try MockHealthFixtures.makeResponse(url: url, statusCode: 200), MockHealthFixtures.legacyOmittedCapabilitiesJSON)
        }
        defer { scope.tearDown() }

        let healthService = ServerHealthService(session: scope.session)
        let appState = AppState(
            baseURL: scope.baseURL,
            startServices: false,
            healthService: healthService,
            runtimeConfigurationService: configService,
            userDefaults: defaults,
            storage: storage
        )

        await appState.checkServerHealth()

        #expect(appState.serverStatus.isConnected == true)
        #expect(appState.runtimeSupportsStructuredToolCalls == false)
    }

    @Test("checkServerHealth against failing or invalid server sets runtimeSupportsStructuredToolCalls false")
    @MainActor
    func testCheckServerHealthWithFailingServerSetsCapabilityFalse() async throws {
        let (defaults, suiteName, tempDir, storage, configService) = try makeTestEnvironment()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let scope = MockHealthServerScope { _ in
            throw URLError(.cannotConnectToHost)
        }
        defer { scope.tearDown() }

        let healthService = ServerHealthService(session: scope.session)
        let appState = AppState(
            baseURL: scope.baseURL,
            startServices: false,
            healthService: healthService,
            runtimeConfigurationService: configService,
            userDefaults: defaults,
            storage: storage
        )

        // Pre-set to true to ensure failure actively resets it
        appState.runtimeSupportsStructuredToolCalls = true
        await appState.checkServerHealth()

        #expect(appState.serverStatus.isConnected == false)
        #expect(appState.runtimeSupportsStructuredToolCalls == false)
    }

    @Test("Capability loss on subsequent health check clears active transient agent modes")
    @MainActor
    func testCapabilityLossClearsActiveAgentModes() async throws {
        let (defaults, suiteName, tempDir, storage, configService) = try makeTestEnvironment()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let scope = MockHealthServerScope { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            return (try MockHealthFixtures.makeResponse(url: url, statusCode: 200), MockHealthFixtures.capableIdentityJSON)
        }
        defer { scope.tearDown() }

        let healthService = ServerHealthService(session: scope.session)
        let appState = AppState(
            baseURL: scope.baseURL,
            startServices: false,
            healthService: healthService,
            runtimeConfigurationService: configService,
            userDefaults: defaults,
            storage: storage
        )
        appState.isAgentPreviewEnabled = true

        // 1. Initial health check: capable server -> runtime capability enabled
        await appState.checkServerHealth()
        #expect(appState.runtimeSupportsStructuredToolCalls == true)

        let conversation = Conversation(
            title: "Workspace Task",
            projectPath: "/Users/example/Workspace"
        )
        appState.conversations = [conversation]

        // 2. Enable agent mode for the conversation
        #expect(appState.canEnableAgentMode(for: conversation.id) == true)
        appState.setAgentMode(true, for: conversation.id)
        #expect(appState.isAgentModeEnabled(for: conversation.id) == true)

        // 3. Server capability loss (transitions to legacy runtime without tool calls)
        scope.updateHandler { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            return (try MockHealthFixtures.makeResponse(url: url, statusCode: 200), MockHealthFixtures.legacyOmittedCapabilitiesJSON)
        }

        await appState.checkServerHealth()

        // 4. Verify runtimeSupportsStructuredToolCalls is now false and transient agent mode is cleared
        #expect(appState.runtimeSupportsStructuredToolCalls == false)
        #expect(appState.isAgentModeEnabled(for: conversation.id) == false)
        #expect(appState.canEnableAgentMode(for: conversation.id) == false)
    }

    @Test("Startup health flow sets runtimeSupportsStructuredToolCalls from verified identity")
    @MainActor
    func testStartupHealthFlowSetsCapabilityFromVerifiedIdentity() async throws {
        let (defaults, suiteName, tempDir, storage, configService) = try makeTestEnvironment()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let scope = MockHealthServerScope { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }
            return (try MockHealthFixtures.makeResponse(url: url, statusCode: 200), MockHealthFixtures.capableIdentityJSON)
        }
        defer { scope.tearDown() }

        let healthService = ServerHealthService(session: scope.session)
        let appState = AppState(
            baseURL: scope.baseURL,
            startServices: true,
            healthService: healthService,
            runtimeConfigurationService: configService,
            userDefaults: defaults,
            storage: storage
        )

        // Wait for startup health check task to complete
        try await AsyncCondition.wait(
            timeout: .seconds(3),
            pollInterval: .milliseconds(20),
            description: "startup health check completion"
        ) {
            appState.serverStatus.isConnected && appState.runtimeSupportsStructuredToolCalls
        }

        #expect(appState.serverStatus.isConnected == true)
        #expect(appState.runtimeSupportsStructuredToolCalls == true)
    }

    @Test("Health check result for endpoint A arriving after baseURL changed to B cannot grant capability to B")
    @MainActor
    func testLateArrivingHealthResultForOldEndpointCannotGrantCapabilityToNewEndpoint() async throws {
        let (defaults, suiteName, tempDir, storage, configService) = try makeTestEnvironment()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDir)
        }

        final class ThreadSafeGate: @unchecked Sendable {
            private let lock = NSLock()
            private var _hit = false
            private var _released = false

            var isHit: Bool {
                lock.lock()
                defer { lock.unlock() }
                return _hit
            }

            var isReleased: Bool {
                lock.lock()
                defer { lock.unlock() }
                return _released
            }

            func markHit() {
                lock.lock()
                defer { lock.unlock() }
                _hit = true
            }

            func release() {
                lock.lock()
                defer { lock.unlock() }
                _released = true
            }
        }

        let gate = ThreadSafeGate()

        let scopeA = MockHealthServerScope { request in
            guard let url = request.url else { throw URLError(.badURL) }
            guard url.path == "/v1/engine" else {
                return (try MockHealthFixtures.makeResponse(url: url, statusCode: 404), Data())
            }
            gate.markHit()
            let timeout = CFAbsoluteTimeGetCurrent() + 5.0
            while !gate.isReleased && CFAbsoluteTimeGetCurrent() < timeout {
                Thread.sleep(forTimeInterval: 0.01)
            }
            return (try MockHealthFixtures.makeResponse(url: url, statusCode: 200), MockHealthFixtures.capableIdentityJSON)
        }
        defer {
            gate.release()
            scopeA.tearDown()
        }

        let scopeB = MockHealthServerScope { request in
            guard let url = request.url else { throw URLError(.badURL) }
            guard url.path == "/v1/engine" else {
                return (try MockHealthFixtures.makeResponse(url: url, statusCode: 404), Data())
            }
            return (try MockHealthFixtures.makeResponse(url: url, statusCode: 200), MockHealthFixtures.legacyOmittedCapabilitiesJSON)
        }
        defer { scopeB.tearDown() }

        let healthService = ServerHealthService(session: scopeA.session)
        let appState = AppState(
            baseURL: scopeA.baseURL,
            startServices: false,
            healthService: healthService,
            runtimeConfigurationService: configService,
            userDefaults: defaults,
            storage: storage
        )
        appState.isAgentPreviewEnabled = true

        // 1. Start health check against scopeA in a task
        let healthTask = Task {
            await appState.checkServerHealth()
        }

        // Wait deterministically for request to hit scopeA
        try await AsyncCondition.wait(description: "scopeA health check entered") {
            gate.isHit
        }

        // 2. User changes baseURL to scopeB while scopeA's health check is in flight
        appState.baseURL = scopeB.baseURL

        // 3. Release scopeA so its health check finishes and returns capable identity
        gate.release()
        await healthTask.value

        // 4. Verification: A's arriving result must NOT grant capability to endpoint B
        #expect(appState.baseURL == scopeB.baseURL)
        #expect(appState.runtimeSupportsStructuredToolCalls == false)
    }

    @Test("Older capable health result cannot overwrite a newer failure for the same endpoint")
    @MainActor
    func testLatestHealthCheckWinsForSameEndpoint() async throws {
        let (defaults, suiteName, tempDir, storage, configService) = try makeTestEnvironment()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDir)
        }

        final class RequestGate: @unchecked Sendable {
            private let lock = NSLock()
            private var requestCount = 0
            private var firstRequestReleased = false

            var firstRequestStarted: Bool {
                lock.withLock { requestCount > 0 }
            }

            func nextRequestNumber() -> Int {
                lock.withLock {
                    requestCount += 1
                    return requestCount
                }
            }

            func releaseFirstRequest() {
                lock.withLock { firstRequestReleased = true }
            }

            func waitForFirstRequestRelease() {
                let timeout = CFAbsoluteTimeGetCurrent() + 5.0
                while CFAbsoluteTimeGetCurrent() < timeout {
                    if lock.withLock({ firstRequestReleased }) { return }
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }
        }

        let gate = RequestGate()
        let scope = MockHealthServerScope { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if gate.nextRequestNumber() == 1 {
                gate.waitForFirstRequestRelease()
                return (
                    try MockHealthFixtures.makeResponse(url: url, statusCode: 200),
                    MockHealthFixtures.capableIdentityJSON
                )
            }
            return (try MockHealthFixtures.makeResponse(url: url, statusCode: 500), Data())
        }
        defer {
            gate.releaseFirstRequest()
            scope.tearDown()
        }

        let appState = AppState(
            baseURL: scope.baseURL,
            startServices: false,
            healthService: ServerHealthService(session: scope.session),
            runtimeConfigurationService: configService,
            userDefaults: defaults,
            storage: storage
        )

        let olderCheck = Task { await appState.checkServerHealth() }
        try await AsyncCondition.wait(description: "first same-endpoint health check entered") {
            gate.firstRequestStarted
        }

        await appState.checkServerHealth()
        #expect(appState.runtimeSupportsStructuredToolCalls == false)

        gate.releaseFirstRequest()
        await olderCheck.value

        #expect(appState.serverStatus.isConnected == false)
        #expect(appState.runtimeSupportsStructuredToolCalls == false)
    }
}
