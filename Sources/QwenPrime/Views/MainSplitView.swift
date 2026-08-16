import SwiftUI

public struct MainSplitView: View {
    @Bindable public var appState: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(appState: appState)
                .navigationSplitViewColumnWidth(
                    min: DesignTokens.Layout.sidebarMinWidth,
                    ideal: DesignTokens.Layout.sidebarIdealWidth,
                    max: DesignTokens.Layout.sidebarMaxWidth
                )
        } detail: {
            ChatView(appState: appState)
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle("")
        .sheet(isPresented: $appState.isSettingsPresented) {
            SettingsView(appState: appState)
        }
    }
}
