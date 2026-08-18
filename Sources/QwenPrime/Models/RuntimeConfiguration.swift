import Foundation

public struct RuntimeModelProfile: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var targetModelPath: String
    public var draftModelPath: String

    public init(
        id: UUID = UUID(),
        name: String = "",
        targetModelPath: String = "",
        draftModelPath: String = ""
    ) {
        self.id = id
        self.name = name
        self.targetModelPath = targetModelPath
        self.draftModelPath = draftModelPath
    }

    public var isConfigured: Bool {
        !targetModelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draftModelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var displaySummary: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unnamed Profile" : trimmed
    }
}

public struct RuntimeConfiguration: Codable, Equatable, Sendable {
    public var targetModelPath: String
    public var draftModelPath: String
    public var activeProfileId: UUID?
    public var profiles: [RuntimeModelProfile]

    public init(
        targetModelPath: String = "",
        draftModelPath: String = "",
        activeProfileId: UUID? = nil,
        profiles: [RuntimeModelProfile] = []
    ) {
        self.targetModelPath = targetModelPath
        self.draftModelPath = draftModelPath
        self.activeProfileId = activeProfileId
        self.profiles = profiles
        self.migrateIfNeeded()
    }

    public var isConfigured: Bool {
        if let active = activeProfile {
            return active.isConfigured
        }
        return !targetModelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draftModelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var activeProfile: RuntimeModelProfile? {
        get {
            guard let id = activeProfileId else { return profiles.first }
            return profiles.first(where: { $0.id == id }) ?? profiles.first
        }
        set {
            guard let newValue else { return }
            if let idx = profiles.firstIndex(where: { $0.id == newValue.id }) {
                profiles[idx] = newValue
            } else {
                profiles.append(newValue)
            }
            activeProfileId = newValue.id
            targetModelPath = newValue.targetModelPath
            draftModelPath = newValue.draftModelPath
        }
    }

    public mutating func migrateIfNeeded() {
        if profiles.isEmpty {
            let hasLegacyPaths = !targetModelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !draftModelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let profile = RuntimeModelProfile(
                name: hasLegacyPaths
                    ? Self.inferredProfileName(targetPath: targetModelPath)
                    : "Hybrid Q8/Q4 + 6-bit MTP",
                targetModelPath: targetModelPath,
                draftModelPath: draftModelPath
            )
            profiles = [profile]
            activeProfileId = profile.id
        } else {
            if activeProfileId == nil || !profiles.contains(where: { $0.id == activeProfileId }) {
                activeProfileId = profiles.first?.id
            }
            if let activeIndex = profiles.firstIndex(where: { $0.id == activeProfileId }) {
                let hasLegacyPair = !targetModelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !draftModelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if hasLegacyPair,
                   (profiles[activeIndex].targetModelPath != targetModelPath
                        || profiles[activeIndex].draftModelPath != draftModelPath) {
                    profiles[activeIndex].targetModelPath = targetModelPath
                    profiles[activeIndex].draftModelPath = draftModelPath
                } else {
                    targetModelPath = profiles[activeIndex].targetModelPath
                    draftModelPath = profiles[activeIndex].draftModelPath
                }
            }
        }
    }

    private static func inferredProfileName(targetPath: String) -> String {
        let modelName = URL(fileURLWithPath: targetPath).lastPathComponent.lowercased()
        if modelName.contains("hybrid") || modelName.contains("q8q4") {
            return "Hybrid Q8/Q4 + 6-bit MTP"
        }
        if modelName.contains("6bit") || modelName.contains("6-bit") {
            return "Uniform 6-bit + 6-bit MTP"
        }
        return "Active Model Pair"
    }

    private enum CodingKeys: String, CodingKey {
        case targetModelPath = "target_model"
        case draftModelPath = "draft_model"
        case activeProfileId = "active_profile_id"
        case profiles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let target = try container.decodeIfPresent(String.self, forKey: .targetModelPath) ?? ""
        let draft = try container.decodeIfPresent(String.self, forKey: .draftModelPath) ?? ""
        let activeId = try container.decodeIfPresent(UUID.self, forKey: .activeProfileId)
        let decodedProfiles = try container.decodeIfPresent([RuntimeModelProfile].self, forKey: .profiles) ?? []

        self.targetModelPath = target
        self.draftModelPath = draft
        self.activeProfileId = activeId
        self.profiles = decodedProfiles
        self.migrateIfNeeded()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let resolvedTarget = activeProfile?.targetModelPath ?? targetModelPath
        let resolvedDraft = activeProfile?.draftModelPath ?? draftModelPath
        try container.encode(resolvedTarget, forKey: .targetModelPath)
        try container.encode(resolvedDraft, forKey: .draftModelPath)
        try container.encode(activeProfileId, forKey: .activeProfileId)
        try container.encode(profiles, forKey: .profiles)
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
