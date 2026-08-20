import SwiftUI

enum ToolExecutionCategory: Equatable {
    case workspaceChange
    case workspaceProcess
    case mcpTool
    case skill
    case workspaceInstructions
    case workspaceRead
    case tool

    init(toolName: String) {
        if ToolName.workspaceMutationTools.contains(toolName) {
            self = .workspaceChange
        } else if ToolNamespace.workspaceProcess.contains(toolName) {
            self = .workspaceProcess
        } else if ToolNamespace.mcp.contains(toolName) {
            self = .mcpTool
        } else if ToolNamespace.skill.contains(toolName) {
            self = .skill
        } else if ToolNamespace.instructions.contains(toolName) {
            self = .workspaceInstructions
        } else if ToolName.workspaceReadTools.contains(toolName) {
            self = .workspaceRead
        } else {
            self = .tool
        }
    }

    var label: String {
        switch self {
        case .workspaceChange: "Workspace Change"
        case .workspaceProcess: "Workspace Process"
        case .mcpTool: "MCP Tool"
        case .skill: "Skill"
        case .workspaceInstructions: "Workspace Instructions"
        case .workspaceRead: "Workspace Read"
        case .tool: "Tool"
        }
    }

    var systemImage: String {
        switch self {
        case .workspaceChange: "pencil.and.list.clipboard"
        case .workspaceProcess: "chevron.left.forwardslash.chevron.right"
        case .mcpTool: "network"
        case .skill: "books.vertical"
        case .workspaceInstructions: "text.book.closed"
        case .workspaceRead: "doc.text.magnifyingglass"
        case .tool: "wrench.and.screwdriver"
        }
    }
}

public struct ToolExecutionCard: View {
    public let execution: ToolExecution
    public let theme: MarkdownTheme

    @State private var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    public init(
        execution: ToolExecution,
        theme: MarkdownTheme = MarkdownTheme.theme(for: .primeDark),
        initiallyExpanded: Bool? = nil
    ) {
        self.execution = execution
        self.theme = theme
        self._isExpanded = State(
            initialValue: initiallyExpanded
                ?? (execution.mutationProposal == nil
                    && !ToolNamespace.skill.contains(execution.toolName)
                    && !ToolNamespace.instructions.contains(execution.toolName))
        )
    }

    private var category: ToolExecutionCategory {
        ToolExecutionCategory(toolName: execution.toolName)
    }

    private var isMCPTool: Bool {
        category == .mcpTool
    }

    private var isSkill: Bool {
        category == .skill
    }

    private var isWorkspaceInstructions: Bool {
        category == .workspaceInstructions
    }

    private var isWorkspaceProcess: Bool {
        category == .workspaceProcess
    }

    private var toolCategoryLabel: String {
        category.label
    }

    private var toolIcon: String {
        category.systemImage
    }

    private var statusDescription: String {
        if let approvalState = execution.approvalState {
            switch approvalState {
            case .pending: return "Approval required"
            case .applying: return "Applying"
            case .approved:
                if isWorkspaceProcess {
                    return execution.isSuccess == true ? "Completed" : "Process failed"
                }
                if isMCPTool {
                    return execution.isSuccess == true ? "Executed" : "Tool failed"
                }
                return "Applied"
            case .rejected: return "Rejected"
            case .failed: return "Failed"
            }
        }
        if execution.isRunning { return "Running" }
        if let success = execution.isSuccess {
            return success
                ? ((isSkill || isWorkspaceInstructions) ? "Loaded" : "Success")
                : "Failed"
        }
        return "Pending"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureCardHeader(
                title: "\(toolCategoryLabel) (\(execution.toolName))",
                accessibilityLabel: "\(toolCategoryLabel): \(execution.toolName), \(statusDescription)",
                systemImage: toolIcon,
                tint: theme.h1,
                isExpanded: $isExpanded,
                metadata: { EmptyView() },
                status: { headerStatus },
                accessory: { EmptyView() }
            )
            .help("\(toolCategoryLabel): \(execution.toolName)")

            if isExpanded {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    // Code Input
                    Text(execution.input)
                        .font(DesignTokens.TextStyle.calloutMonospaced)
                        .foregroundStyle(.primary)
                        .padding(DesignTokens.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            DesignTokens.Surface.recessed(
                                contrast: contrast,
                                reduceTransparency: reduceTransparency
                            ),
                            in: RoundedRectangle(
                                cornerRadius: DesignTokens.Radius.base
                            )
                        )

                    // Output Logs
                    if let output = execution.output, !output.isEmpty {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                            Text("OUTPUT:")
                                .font(
                                    DesignTokens.TextStyle.caption2Monospaced
                                        .weight(.bold)
                                )
                                .foregroundStyle(.tertiary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(output)
                                    .font(DesignTokens.TextStyle.footnoteMonospaced)
                                    .foregroundStyle(
                                        execution.isSuccess == false
                                            ? DesignTokens.Status.danger
                                            : theme.link
                                    )
                                    .lineSpacing(DesignTokens.TextStyle.codeLineSpacing)
                                    .textSelection(.enabled)
                            }
                            .padding(DesignTokens.Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                DesignTokens.Surface.recessed(
                                    contrast: contrast,
                                    reduceTransparency: reduceTransparency
                                ),
                                in: RoundedRectangle(
                                    cornerRadius: DesignTokens.Radius.xs
                                )
                            )
                        }
                        .padding(.top, DesignTokens.Spacing.xxs)
                    }
                }
                .padding(DesignTokens.Spacing.md)
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

    @ViewBuilder
    private var headerStatus: some View {
        if let approvalState = execution.approvalState {
            approvalStatus(approvalState)
        } else if execution.isRunning {
            HStack(spacing: DesignTokens.Spacing.xs) {
                ProgressView()
                    .controlSize(.mini)
                Text("Running")
                    .font(DesignTokens.TextStyle.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        } else if let success = execution.isSuccess {
            HStack(spacing: DesignTokens.Spacing.xxs) {
                Image(
                    systemName: success
                        ? "checkmark.circle.fill"
                        : "xmark.circle.fill"
                )
                .font(DesignTokens.TextStyle.caption)
                .foregroundStyle(
                    success
                        ? DesignTokens.Status.success
                        : DesignTokens.Status.danger
                )
                Text(
                    success
                        ? ((isSkill || isWorkspaceInstructions) ? "Loaded" : "Success")
                        : "Failed"
                )
                .font(DesignTokens.TextStyle.caption2.weight(.medium))
                .foregroundStyle(
                    success
                        ? DesignTokens.Status.success
                        : DesignTokens.Status.danger
                )
            }
        }
    }

    @ViewBuilder
    private func approvalStatus(_ state: ToolApprovalState) -> some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            if state == .applying {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: approvalIcon(state))
                    .foregroundStyle(approvalColor(state))
            }
            Text(statusDescription)
                .font(DesignTokens.TextStyle.caption2.weight(.medium))
                .foregroundStyle(approvalColor(state))
        }
    }

    private func approvalIcon(_ state: ToolApprovalState) -> String {
        switch state {
        case .pending: "exclamationmark.shield"
        case .applying: "hourglass"
        case .approved:
            execution.isSuccess == false
                ? "xmark.circle.fill"
                : "checkmark.circle.fill"
        case .rejected: "xmark.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func approvalColor(_ state: ToolApprovalState) -> Color {
        switch state {
        case .pending: DesignTokens.Status.warning
        case .applying: .secondary
        case .approved:
            execution.isSuccess == false
                ? DesignTokens.Status.danger
                : DesignTokens.Status.success
        case .rejected: .secondary
        case .failed: DesignTokens.Status.danger
        }
    }
}
