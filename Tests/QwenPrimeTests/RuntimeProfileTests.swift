import Foundation
import Testing
@testable import QwenPrime

@Suite("Runtime model profiles")
struct RuntimeProfileTests {
    @Test("Legacy runtime.json migrates into one active profile while preserving Python keys")
    func testLegacyConfigurationMigration() throws {
        let legacy = Data(#"{"target_model":"/models/hybrid","draft_model":"/models/mtp"}"#.utf8)
        let configuration = try JSONDecoder().decode(RuntimeConfiguration.self, from: legacy)

        #expect(configuration.profiles.count == 1)
        #expect(configuration.activeProfile?.targetModelPath == "/models/hybrid")
        #expect(configuration.activeProfile?.draftModelPath == "/models/mtp")

        let encoded = try JSONEncoder().encode(configuration)
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(object["target_model"] as? String == "/models/hybrid")
        #expect(object["draft_model"] as? String == "/models/mtp")
        #expect((object["profiles"] as? [[String: Any]])?.count == 1)
    }

    @Test("Multiple named profiles round-trip with selected pair mirrored to legacy keys")
    func testMultipleProfileRoundTrip() throws {
        let hybrid = RuntimeModelProfile(
            name: "Hybrid Performance",
            targetModelPath: "/models/hybrid",
            draftModelPath: "/models/mtp6"
        )
        let uniform = RuntimeModelProfile(
            name: "Uniform 6-bit",
            targetModelPath: "/models/uniform6",
            draftModelPath: "/models/mtp6"
        )
        let configuration = RuntimeConfiguration(
            targetModelPath: hybrid.targetModelPath,
            draftModelPath: hybrid.draftModelPath,
            activeProfileId: hybrid.id,
            profiles: [hybrid, uniform]
        )

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(RuntimeConfiguration.self, from: data)
        #expect(decoded == configuration)
        #expect(decoded.activeProfile?.name == "Hybrid Performance")
    }

    @Test("Changed legacy keys reconcile into the active saved profile")
    func testLegacyKeyChangeReconcilesActiveProfile() throws {
        let activeID = UUID()
        let object: [String: Any] = [
            "target_model": "/models/new-target",
            "draft_model": "/models/new-draft",
            "active_profile_id": activeID.uuidString,
            "profiles": [[
                "id": activeID.uuidString,
                "name": "Saved Profile",
                "targetModelPath": "/models/old-target",
                "draftModelPath": "/models/old-draft",
            ]],
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(RuntimeConfiguration.self, from: data)

        #expect(decoded.activeProfile?.targetModelPath == "/models/new-target")
        #expect(decoded.activeProfile?.draftModelPath == "/models/new-draft")
    }

    @Test("Hybrid and uniform 6-bit identities are compatible and bind to the selected paths")
    func testIdentityProfilesAndPaths() {
        let draftQuantization = QuantizationIdentity(
            scheme: "uniform",
            bits: [6],
            defaultBits: 6,
            groupSize: 64,
            mode: "affine"
        )
        let hybridProfile = RuntimeModelProfile(
            name: "Hybrid",
            targetModelPath: "/models/hybrid",
            draftModelPath: "/models/mtp"
        )
        let identity = QwenRuntimeIdentity(
            runtimeId: "qwen38-native-mtp-v2",
            targetModelId: "Qwen/Qwen3.8-27B",
            draftModelId: "Qwen/Qwen3.8-27B#native-mtp",
            targetPath: hybridProfile.targetModelPath,
            draftPath: hybridProfile.draftModelPath,
            targetQuantization: QuantizationIdentity(
                scheme: "mixed",
                bits: [4, 8],
                defaultBits: 4,
                groupSize: 64,
                mode: "affine"
            ),
            draftQuantization: draftQuantization,
            blockTokens: 4,
            prefixCacheEnabled: true,
            warmupComplete: true,
            capabilities: ["structured_tool_calls_v1"]
        )

        #expect(identity.isExpectedRuntime)
        #expect(identity.matches(hybridProfile))
        #expect(!identity.matches(RuntimeModelProfile(
            name: "Other",
            targetModelPath: "/models/uniform6",
            draftModelPath: "/models/mtp"
        )))

        let uniformIdentity = QwenRuntimeIdentity(
            runtimeId: identity.runtimeId,
            targetModelId: identity.targetModelId,
            draftModelId: identity.draftModelId,
            targetQuantization: draftQuantization,
            draftQuantization: draftQuantization,
            blockTokens: 4,
            prefixCacheEnabled: true,
            warmupComplete: true
        )
        #expect(uniformIdentity.isExpectedRuntime)
    }

    @Test("Active profile cannot be deleted without first activating another profile")
    @MainActor
    func testActiveProfileDeletionIsRefused() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeProfileDelete-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "RuntimeProfileDelete.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(
            startServices: false,
            runtimeConfigurationService: RuntimeConfigurationService(
                configurationURL: root.appendingPathComponent("runtime.json")
            ),
            userDefaults: defaults,
            storage: StorageService(directoryURL: root.appendingPathComponent("storage"))
        )
        let active = RuntimeModelProfile(name: "Active")
        let alternate = RuntimeModelProfile(name: "Alternate")
        appState.runtimeConfiguration = RuntimeConfiguration(
            activeProfileId: active.id,
            profiles: [active, alternate]
        )

        appState.deleteModelProfile(id: active.id)
        #expect(appState.runtimeConfiguration.profiles.map(\.id) == [active.id, alternate.id])

        appState.deleteModelProfile(id: alternate.id)
        #expect(appState.runtimeConfiguration.profiles.map(\.id) == [active.id])
    }

    @Test("External endpoint blocks switching to a different profile without changing active configuration")
    @MainActor
    func testExternalEndpointBlocksProfileSwitch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RuntimeProfileSwitch-\(UUID().uuidString)", isDirectory: true)
        let targetA = root.appendingPathComponent("hybrid", isDirectory: true)
        let targetB = root.appendingPathComponent("uniform", isDirectory: true)
        let draft = root.appendingPathComponent("mtp", isDirectory: true)
        try FileManager.default.createDirectory(at: targetA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetB, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: draft, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let profileA = RuntimeModelProfile(
            name: "Hybrid",
            targetModelPath: targetA.path,
            draftModelPath: draft.path
        )
        let profileB = RuntimeModelProfile(
            name: "Uniform",
            targetModelPath: targetB.path,
            draftModelPath: draft.path
        )
        let configService = RuntimeConfigurationService(
            configurationURL: root.appendingPathComponent("runtime.json")
        )
        try configService.save(RuntimeConfiguration(
            targetModelPath: profileA.targetModelPath,
            draftModelPath: profileA.draftModelPath,
            activeProfileId: profileA.id,
            profiles: [profileA, profileB]
        ))

        let identityObject: [String: Any] = [
            "runtime_id": "qwen38-native-mtp-v2",
            "target_model_id": "Qwen/Qwen3.8-27B",
            "draft_model_id": "Qwen/Qwen3.8-27B#native-mtp",
            "target_path": targetA.path,
            "draft_path": draft.path,
            "target_quantization": [
                "scheme": "mixed", "bits": [4, 8], "default_bits": 4,
                "group_size": 64, "mode": "affine",
            ],
            "draft_quantization": [
                "scheme": "uniform", "bits": [6], "default_bits": 6,
                "group_size": 64, "mode": "affine",
            ],
            "block_tokens": 4,
            "prefix_cache_enabled": true,
            "warmup_complete": true,
            "capabilities": ["structured_tool_calls_v1"],
        ]
        let identityData = try JSONSerialization.data(withJSONObject: identityObject)
        let scope = MockHealthServerScope { request in
            let url = try #require(request.url)
            return (try MockHealthFixtures.makeResponse(url: url), identityData)
        }
        defer { scope.tearDown() }

        let suiteName = "RuntimeProfileSwitch.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(
            baseURL: scope.baseURL,
            startServices: false,
            healthService: ServerHealthService(session: scope.session),
            runtimeConfigurationService: configService,
            userDefaults: defaults,
            storage: StorageService(directoryURL: root.appendingPathComponent("storage"))
        )

        await appState.checkServerHealth()
        #expect(appState.serverStatus.isConnected)
        appState.activateProfile(id: profileB.id)
        try await AsyncCondition.wait(description: "external profile switch refusal") {
            if case .invalid = appState.runtimeSetupStatus { return true }
            return false
        }

        #expect(appState.runtimeConfiguration.activeProfileId == profileA.id)
        #expect(appState.runtimeConfiguration.targetModelPath == targetA.path)
    }
}
