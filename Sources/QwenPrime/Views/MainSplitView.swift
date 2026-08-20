import SwiftUI

public struct MainSplitView: View {
    @Bindable public var appState: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        if #available(macOS 15.0, *) {
            splitView
                // The detail view owns its feathered backdrop so the sidebar
                // and window controls retain their original transparent chrome.
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            splitView
        }
    }

    private var splitView: some View {
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
    }
}
