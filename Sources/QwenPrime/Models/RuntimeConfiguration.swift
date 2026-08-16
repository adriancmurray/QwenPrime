import Foundation

public struct RuntimeConfiguration: Codable, Equatable, Sendable {
    public var targetModelPath: String
    public var draftModelPath: String

    public init(targetModelPath: String = "", draftModelPath: String = "") {
        self.targetModelPath = targetModelPath
        self.draftModelPath = draftModelPath
    }

    public var isConfigured: Bool {
        !targetModelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draftModelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case targetModelPath = "target_model"
        case draftModelPath = "draft_model"
    }
}

public enum RuntimeSetupStatus: Equatable, Sendable {
    case notConfigured
    case validating
    case ready
    case invalid(String)

    public var message: String {
        switch self {
        case .notConfigured:
            "Choose the Qwen3.8 target and matching native-MTP draft folders."
        case .validating:
            "Validating model provenance and runtime dependencies…"
        case .ready:
            "Qwen3.8 27B target and native-MTP draft are ready."
        case .invalid(let message):
            message
        }
    }
}

public struct RuntimeDoctorResult: Equatable, Sendable {
    public let isReady: Bool
    public let message: String

    public init(isReady: Bool, message: String) {
        self.isReady = isReady
        self.message = message
    }
}
