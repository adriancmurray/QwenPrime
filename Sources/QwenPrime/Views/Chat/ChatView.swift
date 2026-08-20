import AppKit
import SwiftUI

public struct ChatView: View {
    @Bindable public var appState: AppState
    @State private var viewModel = ChatViewModel()
    @State private var thinkingExpandedStates: [UUID: Bool] = [:]
    @State private var isPinnedToLatestMessage = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        Group {
            if let conversation = appState.selectedConversation {
                conversationCanvas(conversation)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        conversationControls(for: conversation)
                    }
            } else {
                NoConversationSelectedView(
                    theme: appState.activeTheme,
                    onCreateConversation: {
                        _ = appState.createNewConversation()
                    }
                )
            }
        }
        .animation(
            reduceMotion ? nil : DesignTokens.AnimationCurve.presentation,
            value: appState.selectedConversationId
        )
        .onChange(of: appState.pendingCommandRequest) { _, request in
            handleCommandRequest(request)
        }
        .onChange(of: Set(appState.conversations.map(\.id))) {
            _, conversationIDs in
            viewModel.retainDrafts(for: conversationIDs)
        }
        .background(appState.activeTheme.windowBackground)
        .overlay(alignment: .top) {
            FeatheredDetailHeaderBackdrop(theme: appState.activeTheme)
                .ignoresSafeArea(edges: .top)
        }
        .tint(appState.activeTheme.h1)
        .toolbar {
            if let conversation = appState.selectedConversation {
                if #available(macOS 26, *) {
                    ToolbarItem(placement: .navigation) {
                        conversationPath(conversation)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .navigation) {
                        conversationPath(conversation)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func conversationControls(for conversation: Conversation) -> some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            let pending = pendingApprovals(in: conversation)
            if let review = pending.first {
                FloatingToolApprovalReview(
                    request: review,
                    pendingCount: pending.count,
                    tint: appState.activeTheme.h1,
                    onApprove: {
                        viewModel.resolveWorkspaceApproval(
                            review,
                            decision: .approve
                        )
                    },
                    onReject: {
                        viewModel.resolveWorkspaceApproval(
                            review,
                            decision: .reject
                        )
                    }
                )
            }

            FloatingComposer(tint: appState.activeTheme.h1) {
                composer(for: conversation)
            }
        }
    }

    private func conversationPath(_ conversation: Conversation) -> some View {
        let workspaceURL = conversation.projectPath
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? appState.sandboxDirectory

        return ConversationPathHeader(
            workspaceName: ProjectScope.displayName(for: workspaceURL),
            conversationTitle: conversation.title
        )
    }

    @ViewBuilder
    private func conversationCanvas(_ conversation: Conversation) -> some View {
        if conversation.messages.isEmpty {
            EmptyConversationView(
                modelName: conversation.modelId,
                theme: appState.activeTheme,
                isRuntimeReady: appState.runtimeSetupStatus == .ready,
                runtimeMessage: appState.runtimeSetupStatus.message,
                onOpenRuntimeSetup: {
                    appState.openSettings(tab: .engine)
                    openSettings()
                }
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    HStack {
                        Spacer(minLength: 0)

                        LazyVStack(spacing: DesignTokens.Spacing.xl) {
                            ForEach(conversation.messages) { message in
                                MessageBubble(
                                    message: message,
                                    theme: appState.activeTheme,
                                    isThinkingExpanded: Binding(
                                        get: {
                                            thinkingExpandedStates[message.id]
                                                ?? message.isThinkingExpanded
                                        },
                                        set: { thinkingExpandedStates[message.id] = $0 }
                                    )
                                )
                                .id(message.id)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(ChatScrollAnchor.latest)
                        }
                        .frame(maxWidth: DesignTokens.Layout.maxContentWidth)
                        .padding(.horizontal, DesignTokens.Spacing.section)
                        .padding(.vertical, DesignTokens.Spacing.xl)

                        Spacer(minLength: 0)
                    }
                }
                .background {
                    ChatScrollPositionObserver { isPinned in
                        isPinnedToLatestMessage = isPinned
                    }
                }
                .onChange(of: conversation.messages.count) { _, _ in
                    autoScrollToBottom(proxy)
                }
                .onChange(of: conversation.messages.last?.content) { _, _ in
                    autoScrollToBottom(proxy)
                }
                .onChange(of: conversation.messages.last?.thinkingContent) { _, _ in
                    autoScrollToBottom(proxy)
                }
                .task(id: conversation.id) {
                    isPinnedToLatestMessage = true
                    await Task.yield()
                    scrollToBottom(proxy)
                }
                .overlay(alignment: .bottomTrailing) {
                    if !isPinnedToLatestMessage {
                        Button {
                            scrollToBottom(proxy)
                        } label: {
                            Label("Jump to Latest", systemImage: "arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Jump to the latest message")
                        .accessibilityLabel("Jump to latest message")
                        .padding(DesignTokens.Spacing.lg)
                    }
                }
            }
        }
    }

    private func composer(for conversation: Conversation) -> some View {
        let workspaceURL = conversation.projectPath
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? appState.sandboxDirectory

        return PromptInputBar(
            text: viewModel.draftBinding(for: conversation.id),
            isThinkingEnabled: Binding(
                get: {
                    appState.conversations.first(where: { $0.id == conversation.id })?
                        .isThinkingEnabled ?? appState.defaultThinkingEnabled
                },
                set: { newValue in
                    appState.updateConversationThinking(
                        id: conversation.id,
                        isEnabled: newValue
                    )
                }
            ),
            isStreaming: appState.isConversationGenerating(conversation.id),
            modelName: conversation.modelId,
            theme: appState.activeTheme,
            sandboxURL: workspaceURL,
            recentProjects: appState.recentProjects,
            onSelectProject: { url in
                appState.setConversationWorkspace(id: conversation.id, url: url)
            },
            onOpenFinder: { appState.openWorkspaceInFinder(workspaceURL) },
            onOpenTerminal: { appState.openWorkspaceInTerminal(workspaceURL) },
            isAgentPreviewVisible: appState.isAgentPreviewEnabled,
            isAgentPreviewAvailable: appState.canAttemptAgentMode(for: conversation.id),
            isAgentPreviewEnabled: appState.isAgentModeEnabled(for: conversation.id),
            onToggleAgentPreview: {
                let current = appState.isAgentModeEnabled(for: conversation.id)
                Task {
                    await appState.setAgentModeAfterRefreshing(
                        !current,
                        for: conversation.id
                    )
                }
            },
            onSend: {
                viewModel.sendMessage(
                    appState: appState,
                    draftText: viewModel.draft(for: conversation.id)
                )
            },
            onStop: {
                viewModel.stopGeneration(
                    conversationID: conversation.id,
                    appState: appState
                )
            }
        )
    }

    private func handleCommandRequest(_ request: AppCommandRequest?) {
        guard let request else { return }
        defer { appState.acknowledgeCommandRequest(id: request.id) }

        guard request.command == .stopGeneration,
              let conversationID = request.conversationID else {
            return
        }
        viewModel.stopGeneration(
            conversationID: conversationID,
            appState: appState
        )
    }

    private func pendingApprovals(in conversation: Conversation) -> [WorkspaceApprovalRequest] {
        viewModel.approvalCoordinator.pendingRequests.filter {
            $0.conversationID == conversation.id
        }
    }

    private func autoScrollToBottom(_ proxy: ScrollViewProxy) {
        guard appState.isAutoScrollEnabled, isPinnedToLatestMessage else { return }
        scrollToBottom(proxy)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        isPinnedToLatestMessage = true
        if reduceMotion {
            proxy.scrollTo(ChatScrollAnchor.latest, anchor: .bottom)
        } else {
            withAnimation(DesignTokens.AnimationCurve.smoothScroll) {
                proxy.scrollTo(ChatScrollAnchor.latest, anchor: .bottom)
            }
        }
    }
}

private struct ConversationPathHeader: View {
    let workspaceName: String
    let conversationTitle: String

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text(workspaceName)
                .foregroundStyle(.secondary)
            Text("/")
                .foregroundStyle(.quaternary)
            Text(conversationTitle)
                .foregroundStyle(.primary)
                .fontWeight(.semibold)
        }
        .font(DesignTokens.TextStyle.body)
        .lineLimit(1)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(workspaceName), \(conversationTitle)")
    }
}

/// Softens only the scrolled detail content behind the toolbar. The effect
/// fades out before it can read as a separate header band.
private struct FeatheredDetailHeaderBackdrop: View {
    let theme: MarkdownTheme

    var body: some View {
        UntintedVisualEffectView()
            .frame(height: DesignTokens.Layout.detailHeaderBackdropHeight)
            .mask {
                LinearGradient(
                    colors: [
                        theme.windowBackground,
                        theme.windowBackground.opacity(
                            DesignTokens.Opacity.strong
                        ),
                        theme.windowBackground.opacity(0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(
                            color: theme.windowBackground.opacity(0),
                            location: 0
                        ),
                        .init(color: theme.windowBackground, location: 0.04),
                        .init(color: theme.windowBackground, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// An AppKit visual effect with neutral content-background blur. It softens
/// sibling content within the app window without applying an app color role.
private struct UntintedVisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.material = .contentBackground
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private enum ChatScrollAnchor {
    static let latest = "chat-latest-message"
}

enum ChatScrollPositionPolicy {
    static func isPinned(
        documentBounds: CGRect,
        visibleRect: CGRect,
        isFlipped: Bool,
        threshold: CGFloat = DesignTokens.Spacing.massive
    ) -> Bool {
        let distanceFromBottom = isFlipped
            ? documentBounds.maxY - visibleRect.maxY
            : visibleRect.minY - documentBounds.minY
        return distanceFromBottom <= threshold
    }
}

private struct ChatScrollPositionObserver: NSViewRepresentable {
    let onPinnedStateChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPinnedStateChange: onPinnedStateChange)
    }

    func makeNSView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.onAttachment = context.coordinator.attach
        return view
    }

    func updateNSView(_ view: AttachmentView, context: Context) {
        context.coordinator.onPinnedStateChange = onPinnedStateChange
        context.coordinator.attach(to: view.enclosingScrollView)
    }

    static func dismantleNSView(_ view: AttachmentView, coordinator: Coordinator) {
        coordinator.attach(to: nil)
        view.onAttachment = nil
    }

    final class AttachmentView: NSView {
        var onAttachment: ((NSScrollView?) -> Void)?

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            onAttachment?(enclosingScrollView)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onAttachment?(enclosingScrollView)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onPinnedStateChange: (Bool) -> Void
        private weak var scrollView: NSScrollView?
        private var wasPostingBoundsChanges = false

        init(onPinnedStateChange: @escaping (Bool) -> Void) {
            self.onPinnedStateChange = onPinnedStateChange
        }

        func attach(to newScrollView: NSScrollView?) {
            guard scrollView !== newScrollView else { return }
            NotificationCenter.default.removeObserver(self)
            if let scrollView {
                scrollView.contentView.postsBoundsChangedNotifications =
                    wasPostingBoundsChanges
            }
            scrollView = newScrollView
            guard let newScrollView else { return }
            wasPostingBoundsChanges =
                newScrollView.contentView.postsBoundsChangedNotifications
            newScrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollBoundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: newScrollView.contentView
            )
        }

        @objc private func scrollBoundsDidChange() {
            guard let scrollView,
                  let documentView = scrollView.documentView else {
                return
            }
            onPinnedStateChange(
                ChatScrollPositionPolicy.isPinned(
                    documentBounds: documentView.bounds,
                    visibleRect: scrollView.documentVisibleRect,
                    isFlipped: documentView.isFlipped
                )
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

public struct NoConversationSelectedView: View {
    public let theme: MarkdownTheme
    public let onCreateConversation: () -> Void

    @State private var isNewConversationHovered = false
    @FocusState private var isNewConversationFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        theme: MarkdownTheme,
        onCreateConversation: @escaping () -> Void = {}
    ) {
        self.theme = theme
        self.onCreateConversation = onCreateConversation
    }

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(DesignTokens.TextStyle.title2.weight(.medium))
                .foregroundStyle(theme.h1)
                .frame(width: 40, height: 40)
                .background(
                    theme.h1.opacity(DesignTokens.Opacity.subtle),
                    in: Circle()
                )
                .accessibilityHidden(true)

            VStack(spacing: DesignTokens.Spacing.xs) {
                Text("Select a conversation")
                    .font(DesignTokens.TextStyle.title3.weight(.semibold))
                    .foregroundStyle(theme.text)

                Text("Choose one from the sidebar, or start a new chat.")
                    .font(DesignTokens.TextStyle.callout)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            Button(action: onCreateConversation) {
                Label("New Conversation", systemImage: "plus")
                    .font(DesignTokens.TextStyle.callout.weight(.semibold))
                    .foregroundStyle(theme.h1)
                    .padding(.horizontal, DesignTokens.Spacing.base)
                    .frame(height: DesignTokens.Layout.toolbarControlHeight)
                    .background(
                        isNewConversationHighlighted
                            ? theme.h1.opacity(DesignTokens.Opacity.hover)
                            : .clear,
                        in: Capsule()
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .focused($isNewConversationFocused)
            .help(AppCommands.newConversation.helpWithShortcut)
            .accessibilityLabel(AppCommands.newConversation.title)
            .onHover { hovering in
                withAnimation(
                    DesignTokens.Motion.animation(
                        DesignTokens.AnimationCurve.hover,
                        reduceMotion: reduceMotion
                    )
                ) {
                    isNewConversationHovered = hovering
                }
            }
        }
        .frame(maxWidth: 360)
        .padding(DesignTokens.Spacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var isNewConversationHighlighted: Bool {
        isNewConversationHovered || isNewConversationFocused
    }
}

public struct EmptyConversationView: View {
    public let modelName: String
    public let theme: MarkdownTheme
    public let isRuntimeReady: Bool
    public let runtimeMessage: String
    public let onOpenRuntimeSetup: () -> Void

    public init(
        modelName: String,
        theme: MarkdownTheme,
        isRuntimeReady: Bool = true,
        runtimeMessage: String = "",
        onOpenRuntimeSetup: @escaping () -> Void = {}
    ) {
        self.modelName = modelName
        self.theme = theme
        self.isRuntimeReady = isRuntimeReady
        self.runtimeMessage = runtimeMessage
        self.onOpenRuntimeSetup = onOpenRuntimeSetup
    }

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.section) {
            Spacer()

            VStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "bolt.fill")
                    .font(DesignTokens.TextStyle.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.h1)

                Text("Qwen Prime")
                    .font(DesignTokens.TextStyle.title1.weight(.bold))
                    .foregroundStyle(theme.text)

                Text("Apple Silicon Native • MLX Speculative Engine")
                    .font(DesignTokens.TextStyle.callout)
                    .foregroundStyle(theme.secondaryText)
            }

            if !isRuntimeReady {
                VStack(spacing: DesignTokens.Spacing.base) {
                    Text(runtimeMessage)
                        .font(DesignTokens.TextStyle.callout)
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                    Button("Set Up Local Models…", action: onOpenRuntimeSetup)
                        .buttonStyle(.borderedProminent)
                }
                .padding(DesignTokens.Spacing.xl)
                .frame(maxWidth: 420)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .fill(DesignTokens.Surface.subtle)
                )
            }

            Spacer()
        }
        .padding(DesignTokens.Spacing.section)
    }
}
