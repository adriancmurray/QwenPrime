
import SwiftUI

public struct SettingsView: View {
    @Bindable public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(
                selection: $appState.settingsSelection,
                theme: appState.activeTheme
            )

            selectedSection
        }
        .frame(width: DesignTokens.Layout.settingsWindowWidth, height: DesignTokens.Layout.settingsWindowHeight)
        .tint(appState.activeTheme.h1)
    }

    @ViewBuilder
    private var selectedSection: some View {
        switch appState.settingsSelection {
        case .systemPrompts:
            SystemPromptSettingsTab(appState: appState)
        case .appearance:
            AppearanceSettingsTab(appState: appState)
        case .engine:
            EngineSettingsTab(appState: appState)
        case .sandbox:
            SandboxSettingsTab(appState: appState)
        case .general:
            GeneralSettingsTab(appState: appState)
        case .shortcuts:
            ShortcutsSettingsTab()
        }
    }
}
