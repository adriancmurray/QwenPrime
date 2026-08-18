import Foundation
import Testing
@testable import QwenPrime

@Suite("Workspace instruction settings contract")
struct WorkspaceInstructionSettingsContractTests {
    @Test("General settings exposes automatic AGENTS.md loading and current status")
    func settingsExposeInstructions() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settings = try String(
            contentsOf: sourceRoot.appendingPathComponent(
                "Sources/QwenPrime/Views/Settings/WorkspaceInstructionsSettingsSection.swift"
            ),
            encoding: .utf8
        )
        let general = try String(
            contentsOf: sourceRoot.appendingPathComponent(
                "Sources/QwenPrime/Views/Settings/SettingsView.swift"
            ),
            encoding: .utf8
        )

        #expect(settings.contains("Use root AGENTS.md in Agent mode"))
        #expect(settings.contains("$appState.isWorkspaceInstructionsEnabled"))
        #expect(settings.contains("Root AGENTS.md found"))
        #expect(settings.contains("No root AGENTS.md found"))
        #expect(general.contains("WorkspaceInstructionsSettingsSection(appState: appState)"))
    }
}
