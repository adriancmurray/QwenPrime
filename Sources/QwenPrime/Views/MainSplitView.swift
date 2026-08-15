import SwiftUI

public struct MainSplitView: View {
    @Bindable public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            ChatView(appState: appState)
        }
        .sheet(isPresented: $appState.isSettingsPresented) {
            SettingsView(appState: appState)
        }
    }
}
