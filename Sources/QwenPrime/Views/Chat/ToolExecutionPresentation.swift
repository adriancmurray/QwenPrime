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
    private static let quietWorkspaceReadTools: Set<String> = [
        "workspace_find_files",
        "workspace_list_directory",
        "workspace_read_file",
        "workspace_search_text",
    ]

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
        quietWorkspaceReadTools.contains(execution.toolName)
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
            Button {
                withAnimation(reduceMotion ? nil : DesignTokens.AnimationCurve.spring) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: DesignTokens.Typography.footnote))
                        .foregroundStyle(Color.cyan)

                    Text(title)
                        .font(.system(size: DesignTokens.Typography.subheadline, weight: .semibold))

                    Text("\(executions.count) steps")
                        .font(.system(size: DesignTokens.Typography.caption2, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if isRunning {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: DesignTokens.Typography.caption))
                            .foregroundStyle(Color.green)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: DesignTokens.Typography.caption2))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, DesignTokens.Spacing.base)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .background(Color.black.opacity(DesignTokens.Opacity.prominent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(executions.count) read-only steps")
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
                .background(Color.white.opacity(DesignTokens.Opacity.faint))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .padding(.vertical, DesignTokens.Spacing.xs)
    }
}
