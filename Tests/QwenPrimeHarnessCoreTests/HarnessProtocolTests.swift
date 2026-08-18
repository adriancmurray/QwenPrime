import Foundation
import Testing
@testable import QwenPrimeHarnessProtocol

@Suite("Qwen Prime harness protocol")
struct HarnessProtocolTests {
    @Test("Versioned request and response round-trip without exposing credentials")
    func requestResponseRoundTrip() throws {
        let request = HarnessRequest(
            protocolVersion: HarnessProtocolVersion.current,
            requestID: UUID(),
            credential: HarnessCredential("super-secret"),
            operation: .swiftTest,
            taskRoot: "/tmp/task-root",
            workingDirectory: "workspace",
            filter: "FixtureTests"
        )
        let data = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(HarnessRequest.self, from: data) == request)
        #expect(String(describing: request.credential) == "<redacted>")
        #expect(!String(describing: request).contains("super-secret"))

        let response = HarnessResponse(
            protocolVersion: HarnessProtocolVersion.current,
            requestID: request.requestID,
            status: .completed,
            capabilities: [.swiftBuild, .swiftTest],
            exitCode: 0,
            stdout: "passed",
            stderr: "",
            outputTruncated: false,
            durationSeconds: 0.5,
            error: nil
        )
        #expect(try JSONDecoder().decode(HarnessResponse.self, from: JSONEncoder().encode(response)) == response)
    }

    @Test("Self-test is a distinct typed operation")
    func selfTestOperation() {
        #expect(HarnessOperation.selfTest.rawValue == "self_test")
        #expect(HarnessCapability.swiftTest.rawValue == "swift_test_v1")
    }
}
