import Foundation
import Testing

@Suite("Standard form controls")
struct StandardFormControlTests {
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test("Shared form-control style uses the semantic native size")
    func sharedStyleUsesSemanticNativeSize() throws {
        let tokens = try source(at: "Sources/QwenPrime/Theme/DesignTokens.swift")
        let modifier = try source(
            at: "Sources/QwenPrime/Views/Shared/StandardFormControl.swift"
        )

        #expect(tokens.contains("public static let formSize: ControlSize = .regular"))
        #expect(modifier.contains("controlSize(DesignTokens.Control.formSize)"))
    }

    @Test("Engine profile picker and adjacent action share the form style")
    func engineProfileControlsUseSharedFormStyle() throws {
        let engine = try source(
            at: "Sources/QwenPrime/Views/Settings/EngineSettingsTab.swift"
        )

        #expect(engine.contains(".pickerStyle(.menu)\n              .standardFormControl()"))
        #expect(engine.contains(".buttonStyle(.bordered)\n              .standardFormControl()"))
    }

    @Test("Settings reserve compact sizing for progress feedback only")
    func settingsDoNotUseCompactRegularControls() throws {
        let settingsDirectory = projectRoot.appendingPathComponent(
            "Sources/QwenPrime/Views/Settings"
        )
        let files = try swiftFiles(in: settingsDirectory)
        let compactControls = try files.flatMap { file in
            try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n")
                .filter { $0.contains(".controlSize(.small)") }
                .map { "\(file.lastPathComponent): \($0.trimmingCharacters(in: .whitespaces))" }
        }

        #expect(compactControls == [
            "MCPServersSettingsSection.swift: ProgressView().controlSize(.small)"
        ])
    }

    private func source(at relativePath: String) throws -> String {
        try String(
            contentsOf: projectRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        return try files.flatMap { file in
            let values = try file.resourceValues(forKeys: keys)
            if values.isRegularFile == true, file.pathExtension == "swift" {
                return [file]
            }
            return []
        }
    }
}
