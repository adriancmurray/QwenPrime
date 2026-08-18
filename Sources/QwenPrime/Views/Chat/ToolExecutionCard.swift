import SwiftUI

public struct ToolExecutionCard: View {
    public let execution: ToolExecution
    public let theme: MarkdownTheme

    @State private var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        execution: ToolExecution,
        theme: MarkdownTheme = MarkdownTheme.theme(for: .primeDark)
    ) {
        self.execution = execution
        self.theme = theme
        self._isExpanded = State(
            initialValue: execution.mutationProposal == nil
                && !execution.toolName.hasPrefix("skill__")
        )
    }

    private var isWorkspaceTool: Bool {
        execution.toolName.hasPrefix("workspace_")
    }

    private var isMCPTool: Bool {
        execution.toolName.hasPrefix("mcp__")
    }

    private var isSkill: Bool {
        execution.toolName.hasPrefix("skill__")
    }

    private var isWorkspaceMutation: Bool {
        execution.toolName == "workspace_write_file"
            || execution.toolName == "workspace_apply_patch"
    }

    private var isWorkspaceCommand: Bool {
        execution.toolName == "workspace_run_command"
    }

    private var isWorkspaceTask: Bool {
        execution.toolName == "workspace_run_task"
    }

    private var toolCategoryLabel: String {
        if isWorkspaceMutation { return "Workspace Change" }
        if isWorkspaceTask { return "Workspace Task" }
        if isWorkspaceCommand { return "Workspace Command" }
        if isMCPTool { return "MCP Tool" }
        if isSkill { return "Skill" }
        return isWorkspaceTool ? "Workspace Read" : "Tool"
    }

    private var toolIcon: String {
        if isWorkspaceMutation { return "pencil.and.list.clipboard" }
        if isWorkspaceTask { return "hammer" }
        if isWorkspaceCommand { return "chevron.left.forwardslash.chevron.right" }
        if isMCPTool { return "network" }
        if isSkill { return "books.vertical" }
        return isWorkspaceTool ? "doc.text.magnifyingglass" : "wrench.and.screwdriver"
    }

    private var statusDescription: String {
        if let approvalState = execution.approvalState {
            switch approvalState {
            case .pending: return "Approval required"
            case .applying: return "Applying"
            case .approved:
                if isWorkspaceTask {
                    return execution.isSuccess == true ? "Completed" : "Task failed"
                }
                if isWorkspaceCommand {
                    return execution.isSuccess == true ? "Executed" : "Command failed"
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
            return success ? (isSkill ? "Loaded" : "Success") : "Failed"
        }
        return "Pending"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Bar
            Button {
                withAnimation(reduceMotion ? nil : DesignTokens.AnimationCurve.spring) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: DesignTokens.Spacing.md) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Image(systemName: toolIcon)
                            .font(.system(size: DesignTokens.Typography.footnote))
                            .foregroundStyle(Color.cyan)

                        Text("\(toolCategoryLabel) (\(execution.toolName))")
                            .font(.system(size: DesignTokens.Typography.subheadline, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    // Status Pill
                    if let approvalState = execution.approvalState {
                        approvalStatus(approvalState)
                    } else if execution.isRunning {
                        HStack(spacing: DesignTokens.Spacing.xs) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Running")
                                .font(.system(size: DesignTokens.Typography.caption2, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    } else if let success = execution.isSuccess {
                        HStack(spacing: DesignTokens.Spacing.xxs) {
                            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: DesignTokens.Typography.caption))
                                .foregroundStyle(success ? Color.green : Color.red)
                            Text(success ? (isSkill ? "Loaded" : "Success") : "Failed")
                                .font(.system(size: DesignTokens.Typography.caption2, weight: .medium))
                                .foregroundStyle(success ? Color.green : Color.red)
                        }
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(toolCategoryLabel): \(execution.toolName), \(statusDescription)")
            .help("\(toolCategoryLabel): \(execution.toolName)")

            if isExpanded {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    // Code Input
                    Text(execution.input)
                        .font(.system(size: DesignTokens.Typography.subheadline, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(DesignTokens.Opacity.high))
                        .padding(DesignTokens.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.base))

                    // Output Logs
                    if let output = execution.output, !output.isEmpty {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                            Text("OUTPUT:")
                                .font(.system(size: DesignTokens.Typography.micro, weight: .bold, design: .monospaced))
                                .foregroundStyle(.tertiary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(output)
                                    .font(.system(size: DesignTokens.Typography.footnote, weight: .regular, design: .monospaced))
                                    .foregroundStyle(execution.isSuccess == false ? Color.red.opacity(0.9) : Color.cyan.opacity(0.9))
                                    .lineSpacing(DesignTokens.Typography.lineSpacingCode)
                                    .textSelection(.enabled)
                            }
                            .padding(DesignTokens.Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                        }
                        .padding(.top, DesignTokens.Spacing.xxs)
                    }
                }
                .padding(DesignTokens.Spacing.md)
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
                .font(.system(size: DesignTokens.Typography.caption2, weight: .medium))
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
        case .pending: .orange
        case .applying: .secondary
        case .approved: execution.isSuccess == false ? .red : .green
        case .rejected: .secondary
        case .failed: .red
        }
    }
}
