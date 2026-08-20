import AppKit
import SwiftUI

public enum ThemeType: String, CaseIterable, Identifiable, Codable, Sendable {
    case primeDark = "Prime Dark"
    case cyberpunk = "Cyberpunk Neon"
    case dracula = "Dracula"
    case nord = "Nordic Frost"
    case monochrome = "Monochrome Studio"

    public var id: String { rawValue }
}

public struct MarkdownTheme: Sendable {
    private static let standardCodeBlockBorderOpacity = 0.14
    private static let increasedCodeBlockBorderOpacity = 0.38
    private static let standardThinkingBorderOpacity = 0.38
    private static let increasedThinkingBorderOpacity = 0.7

    public var id: ThemeType
    public var name: String

    // Typography & Content Colors
    public var text: Color
    public var secondaryText: Color
    public var windowBackground: Color
    public var controlBackground: Color
    public var selectedControlText: Color
    public var h1: Color
    public var h2: Color
    public var h3: Color
    public var boldText: Color
    public var link: Color

    // Code & Quotes
    public var inlineCodeText: Color
    public var inlineCodeBackground: Color
    public var codeBlockBackground: Color
    public var codeBlockHeaderBackground: Color
    public var codeBlockBorder: Color
    public var quoteBorder: Color
    public var quoteBackground: Color
    public var bulletColor: Color

    // Bubbles & Backgrounds
    public var userBubbleGradient: [Color]
    public var userTextColor: Color
    public var assistantBackground: Color
    public var thinkingHeaderBackground: Color
    public var thinkingBorder: Color

    public static func theme(for type: ThemeType) -> MarkdownTheme {
        let palette = Palette.palette(for: type)
        return MarkdownTheme(
            id: type,
            name: type.rawValue,
            text: .primary,
            secondaryText: .secondary,
            windowBackground: Color(nsColor: .windowBackgroundColor),
            controlBackground: Color(nsColor: .controlBackgroundColor),
            selectedControlText: Color(nsColor: .selectedControlTextColor),
            h1: palette.primary,
            h2: palette.secondary,
            h3: palette.tertiary,
            boldText: .primary,
            link: palette.secondary,
            inlineCodeText: palette.tertiary,
            inlineCodeBackground: palette.tertiary.opacity(0.12),
            codeBlockBackground: Color(nsColor: .textBackgroundColor),
            codeBlockHeaderBackground: Color(nsColor: .controlBackgroundColor),
            codeBlockBorder: Color.primary.opacity(
                standardCodeBlockBorderOpacity
            ),
            quoteBorder: palette.primary.opacity(0.72),
            quoteBackground: palette.primary.opacity(0.08),
            bulletColor: palette.secondary,
            userBubbleGradient: palette.userBubbleGradient,
            userTextColor: .white,
            assistantBackground: .clear,
            thinkingHeaderBackground: palette.primary.opacity(0.1),
            thinkingBorder: palette.primary.opacity(
                standardThinkingBorderOpacity
            )
        )
    }

    /// Re-resolves contrast-sensitive roles without changing the selected
    /// palette. Renderers can use this while the system appearance changes.
    public func resolved(for contrast: ColorSchemeContrast) -> MarkdownTheme {
        var resolved = self
        resolved.text = .primary
        resolved.secondaryText = .secondary
        resolved.boldText = .primary
        resolved.codeBlockBorder = Color.primary.opacity(
            contrast == .increased
                ? Self.increasedCodeBlockBorderOpacity
                : Self.standardCodeBlockBorderOpacity
        )
        resolved.thinkingBorder = h1.opacity(
            contrast == .increased
                ? Self.increasedThinkingBorderOpacity
                : Self.standardThinkingBorderOpacity
        )
        return resolved
    }

    private struct Palette {
        let primary: Color
        let secondary: Color
        let tertiary: Color
        let userBubbleGradient: [Color]

        static func palette(for type: ThemeType) -> Palette {
            switch type {
            case .primeDark:
                Palette(
                    primary: .cyan,
                    secondary: .blue,
                    tertiary: .indigo,
                    userBubbleGradient: [
                        Color.blue.opacity(0.88),
                        Color.indigo.opacity(0.94),
                    ]
                )
            case .cyberpunk:
                Palette(
                    primary: .yellow,
                    secondary: .pink,
                    tertiary: .cyan,
                    userBubbleGradient: [
                        Color.pink.opacity(0.88),
                        Color.purple.opacity(0.94),
                    ]
                )
            case .dracula:
                Palette(
                    primary: Color(red: 0.58, green: 0.36, blue: 0.9),
                    secondary: Color(red: 0.18, green: 0.62, blue: 0.78),
                    tertiary: Color(red: 0.2, green: 0.65, blue: 0.35),
                    userBubbleGradient: [
                        Color(red: 0.38, green: 0.31, blue: 0.62),
                        Color(red: 0.26, green: 0.22, blue: 0.44),
                    ]
                )
            case .nord:
                Palette(
                    primary: Color(red: 0.3, green: 0.58, blue: 0.68),
                    secondary: Color(red: 0.32, green: 0.58, blue: 0.55),
                    tertiary: Color(red: 0.72, green: 0.54, blue: 0.2),
                    userBubbleGradient: [
                        Color(red: 0.32, green: 0.48, blue: 0.64),
                        Color(red: 0.24, green: 0.34, blue: 0.5),
                    ]
                )
            case .monochrome:
                Palette(
                    primary: .primary,
                    secondary: .secondary,
                    tertiary: .primary.opacity(0.82),
                    userBubbleGradient: [
                        Color(nsColor: .darkGray),
                        Color(nsColor: .black),
                    ]
                )
            }
        }
    }
}
