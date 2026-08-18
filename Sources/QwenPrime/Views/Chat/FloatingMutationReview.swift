import SwiftUI

public struct FloatingMutationReview: View {
    public let execution: ToolExecution
    public let pendingCount: Int
    public let tint: Color
    public let onApprove: () -> Void
    public let onReject: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        execution: ToolExecution,
        pendingCount: Int,
        tint: Color,
        onApprove: @escaping () -> Void,
        onReject: @escaping () -> Void
    ) {
        self.execution = execution
        self.pendingCount = pendingCount
        self.tint = tint
        self.onApprove = onApprove
        self.onReject = onReject
    }

    public var body: some View {
        if let mutationProposal = execution.mutationProposal {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "pencil.and.list.clipboard")
                        .foregroundStyle(tint)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text("Review workspace change")
                            .font(.system(size: DesignTokens.Typography.callout, weight: .semibold))
                        Text(mutationProposal.relativePath)
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
                    Text(mutationProposal.preview)
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
                    Text("Nothing changes until you apply this diff.")
                        .font(.system(size: DesignTokens.Typography.caption))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Reject", action: onReject)
                        .buttonStyle(.bordered)
                        .help("Reject this change without modifying the workspace")

                    Button("Apply", action: onApprove)
                        .buttonStyle(.borderedProminent)
                        .help("Apply the reviewed change to \(mutationProposal.relativePath)")
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
            .accessibilityLabel("Review change to \(mutationProposal.relativePath)")
        }
    }
}
