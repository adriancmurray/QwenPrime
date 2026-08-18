import SwiftUI

public struct FloatingToolApprovalReview: View {
    public let request: WorkspaceApprovalRequest
    public let pendingCount: Int
    public let tint: Color
    public let onApprove: () -> Void
    public let onReject: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        request: WorkspaceApprovalRequest,
        pendingCount: Int,
        tint: Color,
        onApprove: @escaping () -> Void,
        onReject: @escaping () -> Void
    ) {
        self.request = request
        self.pendingCount = pendingCount
        self.tint = tint
        self.onApprove = onApprove
        self.onReject = onReject
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: isWorkspaceTask ? "hammer" : "pencil.and.list.clipboard")
                        .foregroundStyle(tint)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text(title)
                            .font(.system(size: DesignTokens.Typography.callout, weight: .semibold))
                        Text(subject)
                            .font(.system(size: DesignTokens.Typography.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if pendingCount > 1 {
                        Text("1 of \(pendingCount)")
                            .font(.system(size: DesignTokens.Typography.caption2, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                ScrollView([.horizontal, .vertical]) {
                    Text(preview)
                        .font(.system(size: DesignTokens.Typography.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 132)
                .padding(DesignTokens.Spacing.sm)
                .background(
                    Color.black.opacity(DesignTokens.Opacity.prominent),
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.base)
                )

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(footnote)
                        .font(.system(size: DesignTokens.Typography.caption))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Reject", action: onReject)
                        .buttonStyle(.bordered)
                        .help(rejectHelp)

                    Button(approveTitle, action: onApprove)
                        .buttonStyle(.borderedProminent)
                        .help(approveHelp)
                }
            }
            .padding(DesignTokens.Spacing.lg)
            .frame(maxWidth: DesignTokens.Layout.composerMaxWidth)
            .primeGlassSurface(
                cornerRadius: DesignTokens.Radius.xl,
                tint: tint.opacity(0.1),
                isInteractive: true
            )
            .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
            .padding(.horizontal, DesignTokens.Spacing.section)
            .transition(
                reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .move(edge: .bottom))
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(title): \(subject)")
    }

    private var title: String {
        switch request.payload {
        case .mutation(let proposal):
            proposal.operation == .changeSet
                ? "Agent paused · Review workspace changes"
                : "Agent paused · Review workspace change"
        case .command:
            isWorkspaceTask
                ? "Agent paused · Review task"
                : "Agent paused · Review command"
        }
    }

    private var subject: String {
        switch request.payload {
        case .mutation(let proposal): proposal.relativePath
        case .command(let proposal):
            isWorkspaceTask
                ? ([proposal.command] + proposal.arguments.prefix(1)).joined(separator: " ")
                : proposal.command
        }
    }

    private var preview: String {
        switch request.payload {
        case .mutation(let proposal): proposal.preview
        case .command(let proposal): proposal.preview
        }
    }

    private var footnote: String {
        switch request.payload {
        case .mutation: "Nothing changes until you apply this diff."
        case .command:
            isWorkspaceTask
                ? "The task runs only after approval in a network-isolated build environment using a staged package copy. The original workspace remains unchanged."
                : "The command runs only after approval in the sandboxed helper."
        }
    }

    private var approveTitle: String {
        switch request.payload {
        case .mutation: "Apply"
        case .command: isWorkspaceTask ? "Run Task" : "Run"
        }
    }

    private var approveHelp: String {
        switch request.payload {
        case .mutation(let proposal):
            proposal.operation == .changeSet
                ? "Apply all reviewed workspace changes"
                : "Apply the reviewed change to \(proposal.relativePath)"
        case .command:
            isWorkspaceTask
                ? "Run the reviewed build or test task"
                : "Run the reviewed command in the sandboxed helper"
        }
    }

    private var rejectHelp: String {
        isWorkspaceTask
            ? "Reject this task without running workspace code"
            : "Reject this change without modifying the workspace"
    }

    private var isWorkspaceTask: Bool {
        request.toolName == "workspace_run_task"
    }
}
