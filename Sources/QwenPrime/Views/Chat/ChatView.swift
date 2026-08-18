import SwiftUI
import AppKit

public struct ChatView: View {
    @Bindable public var appState: AppState
    @State private var viewModel = ChatViewModel()
    @State private var thinkingExpandedStates: [UUID: Bool] = [:]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            if let conversation = appState.selectedConversation {
                conversationCanvas(conversation)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

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
            } else {
                ContentUnavailableView(
                    "No Conversation Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Select or create a conversation from the sidebar.")
                )
            }
        }
        .animation(
            reduceMotion ? nil : DesignTokens.AnimationCurve.presentation,
            value: appState.selectedConversationId
        )
        .background(Color(nsColor: .windowBackgroundColor))
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
        .alert(
            "Workspace Access Failed",
            isPresented: Binding(
                get: { appState.workspaceAuthorizationError != nil },
                set: { if !$0 { appState.clearWorkspaceAuthorizationError() } }
            )
        ) {
            Button("OK") { appState.clearWorkspaceAuthorizationError() }
        } message: {
            Text(appState.workspaceAuthorizationError ?? "The selected workspace could not be authorized.")
        }
    }

    private func conversationPath(_ conversation: Conversation) -> some View {
        let folder = conversation.projectPath
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? appState.sandboxDirectory.lastPathComponent

        return HStack(spacing: DesignTokens.Spacing.sm) {
            Text(folder)
                .foregroundStyle(.secondary)
            Text("/")
                .foregroundStyle(.quaternary)
            Text(conversation.title)
                .foregroundStyle(.primary)
                .fontWeight(.semibold)
        }
        .font(.system(size: DesignTokens.Typography.body))
        .lineLimit(1)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(folder), \(conversation.title)")
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
                    appState.settingsSelection = .engine
                    openSettings()
                }
            )
                .padding(.bottom, scrollClearance(for: conversation))
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
                                .id("bottomAnchor")
                        }
                        .frame(maxWidth: DesignTokens.Layout.maxContentWidth)
                        .padding(.horizontal, DesignTokens.Spacing.section)
                        .padding(.vertical, DesignTokens.Spacing.xl)

                        Spacer(minLength: 0)
                    }
                }
                .contentMargins(
                    .bottom,
                    scrollClearance(for: conversation),
                    for: .scrollContent
                )
                .onChange(of: conversation.messages.last?.content) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: conversation.messages.last?.thinkingContent) { _, _ in
                    scrollToBottom(proxy)
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
            text: $viewModel.inputText,
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
            onSend: { viewModel.sendMessage(appState: appState) },
            onStop: {
                viewModel.stopGeneration(
                    conversationID: conversation.id,
                    appState: appState
                )
            }
        )
    }

    private func pendingApprovals(in conversation: Conversation) -> [WorkspaceApprovalRequest] {
        viewModel.approvalCoordinator.pendingRequests.filter {
            $0.conversationID == conversation.id
        }
    }

    private func scrollClearance(for conversation: Conversation) -> CGFloat {
        DesignTokens.Layout.composerScrollClearance
            + (pendingApprovals(in: conversation).isEmpty
                ? 0
                : DesignTokens.Layout.mutationReviewClearance)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo("bottomAnchor", anchor: .bottom)
        } else {
            withAnimation(DesignTokens.AnimationCurve.smoothScroll) {
                proxy.scrollTo("bottomAnchor", anchor: .bottom)
            }
        }
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
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.h1)

                Text("Qwen Prime")
                    .font(.system(size: DesignTokens.Typography.title1, weight: .bold))
                    .foregroundStyle(theme.text)

                Text("Apple Silicon Native • MLX Speculative Engine")
                    .font(.system(size: DesignTokens.Typography.callout))
                    .foregroundStyle(theme.secondaryText)
            }

            if !isRuntimeReady {
                VStack(spacing: DesignTokens.Spacing.base) {
                    Text(runtimeMessage)
                        .font(.system(size: DesignTokens.Typography.callout))
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
