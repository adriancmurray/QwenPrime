import Foundation

public struct RuntimeConfigurationService: Sendable {
    public let configurationURL: URL

    public init(configurationURL: URL? = nil) {
        self.configurationURL = configurationURL ?? Self.defaultConfigurationURL
    }

    public static var defaultConfigurationURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/QwenPrime", isDirectory: true)
            .appendingPathComponent("runtime.json")
    }

    public func load() throws -> RuntimeConfiguration? {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            return nil
        }
        return try JSONDecoder().decode(
            RuntimeConfiguration.self,
            from: Data(contentsOf: configurationURL)
        )
    }

    public func save(_ configuration: RuntimeConfiguration) throws {
        let directory = configurationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(configuration)
        data.append(0x0A)
        try data.write(to: configurationURL, options: .atomic)
    }

    public func localValidation(
        _ configuration: RuntimeConfiguration
    ) -> RuntimeSetupStatus {
        guard configuration.isConfigured else {
            return .notConfigured
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: configuration.targetModelPath,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return .invalid("Target model folder does not exist.")
        }
        isDirectory = false
        guard FileManager.default.fileExists(
            atPath: configuration.draftModelPath,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return .invalid("Draft model folder does not exist.")
        }
        return .ready
    }
}
