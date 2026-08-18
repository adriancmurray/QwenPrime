import Foundation

public enum HarnessProtocolVersion {
    public static let current = 1
}

public struct HarnessCredential: Codable, Equatable, Hashable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible {
    private let value: String

    public init(_ value: String) {
        self.value = value
    }

    public func matches(_ candidate: String) -> Bool {
        value == candidate
    }

    public var description: String { "<redacted>" }
    public var debugDescription: String { "<redacted>" }
}

public enum HarnessOperation: String, Codable, Equatable, Sendable {
    case selfTest = "self_test"
    case swiftBuild = "swift_build"
    case swiftTest = "swift_test"
}

public enum HarnessCapability: String, Codable, Equatable, Sendable {
    case selfTest = "self_test_v1"
    case swiftBuild = "swift_build_v1"
    case swiftTest = "swift_test_v1"
}

public struct HarnessRequest: Codable, Equatable, Sendable, CustomStringConvertible {
    public let protocolVersion: Int
    public let requestID: UUID
    public let credential: HarnessCredential
    public let operation: HarnessOperation
    public let taskRoot: String
    public let workingDirectory: String
    public let filter: String?

    public init(
        protocolVersion: Int,
        requestID: UUID,
        credential: HarnessCredential,
        operation: HarnessOperation,
        taskRoot: String,
        workingDirectory: String,
        filter: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.credential = credential
        self.operation = operation
        self.taskRoot = taskRoot
        self.workingDirectory = workingDirectory
        self.filter = filter
    }

    public var description: String {
        "HarnessRequest(protocolVersion: \(protocolVersion), requestID: \(requestID), credential: <redacted>, operation: \(operation.rawValue), taskRoot: \(taskRoot), workingDirectory: \(workingDirectory))"
    }
}

public enum HarnessResponseStatus: String, Codable, Equatable, Sendable {
    case ready
    case completed
    case failed
    case rejected
}

public struct HarnessResponse: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let requestID: UUID
    public let status: HarnessResponseStatus
    public let capabilities: [HarnessCapability]
    public let exitCode: Int32?
    public let stdout: String
    public let stderr: String
    public let outputTruncated: Bool
    public let durationSeconds: Double
    public let error: String?

    public init(
        protocolVersion: Int,
        requestID: UUID,
        status: HarnessResponseStatus,
        capabilities: [HarnessCapability],
        exitCode: Int32?,
        stdout: String,
        stderr: String,
        outputTruncated: Bool,
        durationSeconds: Double,
        error: String?
    ) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.status = status
        self.capabilities = capabilities
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.outputTruncated = outputTruncated
        self.durationSeconds = durationSeconds
        self.error = error
    }
}
