import SwiftUI

public struct CodeBlockView: View {
    public let language: String
    public let code: String

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    public init(language: String = "", code: String) {
        self.language = language.isEmpty ? "text" : language.lowercased()
        self.code = code
    }

    private var languageColor: Color {
        DesignTokens.Syntax.languageColor(for: language)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Bar
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(languageColor)
                        .frame(width: 7, height: 7)

                    Text(language.uppercased())
                        .font(DesignTokens.TextStyle.captionMonospaced.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                CopyFeedbackButton(
                    value: code,
                    label: "Copy code",
                    presentation: .labeled("Copy Code")
                )
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(
                DesignTokens.Surface.adaptiveSubtle(
                    contrast: contrast,
                    reduceTransparency: reduceTransparency
                )
            )

            Divider()
                .opacity(0.2)

            // Code Content
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(DesignTokens.TextStyle.calloutMonospaced)
                    .foregroundStyle(.primary)
                    .lineSpacing(DesignTokens.TextStyle.codeLineSpacing)
                    .padding(.horizontal, DesignTokens.Spacing.xl)
                    .padding(.vertical, DesignTokens.Spacing.lg)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                DesignTokens.Surface.recessed(
                    contrast: contrast,
                    reduceTransparency: reduceTransparency
                )
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .primeCardSurface(cornerRadius: DesignTokens.Radius.lg)
    }
}
