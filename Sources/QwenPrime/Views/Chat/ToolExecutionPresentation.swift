import SwiftUI

public enum ToolExecutionPresentationItem: Identifiable, Equatable {
    case execution(ToolExecution)
    case workspaceReadGroup([ToolExecution])

    public var id: String {
        switch self {
        case .execution(let execution):
            return "execution:\(execution.id)"
        case .workspaceReadGroup(let executions):
            let firstID = executions.first?.id ?? "empty"
            let lastID = executions.last?.id ?? "empty"
            return "workspace-read-group:\(firstID):\(lastID)"
        }
    }
}

public enum ToolExecutionPresentation {
    public static func items(
        for executions: [ToolExecution]
    ) -> [ToolExecutionPresentationItem] {
        var items: [ToolExecutionPresentationItem] = []
        var pendingReads: [ToolExecution] = []

        func flushReads() {
            guard !pendingReads.isEmpty else { return }
            if pendingReads.count == 1, let execution = pendingReads.first {
                items.append(.execution(execution))
            } else {
                items.append(.workspaceReadGroup(pendingReads))
            }
            pendingReads.removeAll(keepingCapacity: true)
        }

        for execution in executions {
            if isQuietWorkspaceRead(execution) {
                pendingReads.append(execution)
            } else {
                flushReads()
                items.append(.execution(execution))
            }
        }
        flushReads()
        return items
    }

    private static func isQuietWorkspaceRead(_ execution: ToolExecution) -> Bool {
        ToolName.quietWorkspaceReadTools.contains(execution.toolName)
            && execution.isSuccess != false
            && execution.approvalState == nil
            && execution.mutationProposal == nil
            && execution.commandProposal == nil
    }
}

public struct WorkspaceReadGroupCard: View {
    public let executions: [ToolExecution]
    public let theme: MarkdownTheme

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    public init(
        executions: [ToolExecution],
        theme: MarkdownTheme = MarkdownTheme.theme(for: .primeDark)
    ) {
        self.executions = executions
        self.theme = theme
    }

    private var isRunning: Bool {
        executions.contains(where: \.isRunning)
    }

    private var title: String {
        isRunning ? "Inspecting workspace" : "Inspected workspace"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureCardHeader(
                title: title,
                accessibilityLabel: "\(title), \(stepCountLabel)",
                systemImage: "doc.text.magnifyingglass",
                tint: theme.h1,
                isExpanded: $isExpanded,
                metadata: {
                    Text(stepCountLabel)
                        .font(DesignTokens.TextStyle.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                },
                status: {
                    if isRunning {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(DesignTokens.TextStyle.caption)
                            .foregroundStyle(DesignTokens.Status.success)
                    }
                },
                accessory: { EmptyView() }
            )
            .help("Show read-only workspace activity")

            if isExpanded {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    ForEach(executions) { execution in
                        ToolExecutionCard(
                            execution: execution,
                            theme: theme,
                            initiallyExpanded: false
                        )
                    }
                }
                .padding(DesignTokens.Spacing.sm)
                .background(
                    DesignTokens.Surface.adaptiveSubtle(
                        contrast: contrast,
                        reduceTransparency: reduceTransparency
                    )
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .primeCardSurface(cornerRadius: DesignTokens.Radius.md)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .animation(
            reduceMotion ? nil : DesignTokens.AnimationCurve.fast,
            value: isExpanded
        )
    }

    private var stepCountLabel: String {
        PresentationFormatting.count(executions.count, unit: .step)
    }
}
