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
    public var id: ThemeType
    public var name: String

    // Typography & Content Colors
    public var text: Color
    public var secondaryText: Color
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
        switch type {
        case .primeDark:
            return MarkdownTheme(
                id: .primeDark,
                name: "Prime Dark",
                text: Color(white: 0.92),
                secondaryText: Color(white: 0.65),
                h1: Color.cyan,
                h2: Color.white,
                h3: Color(white: 0.88),
                boldText: Color.white,
                link: Color.cyan,
                inlineCodeText: Color.cyan.opacity(0.95),
                inlineCodeBackground: Color.cyan.opacity(0.12),
                codeBlockBackground: Color.black.opacity(0.55),
                codeBlockHeaderBackground: Color(white: 0.12),
                codeBlockBorder: Color.white.opacity(0.1),
                quoteBorder: Color.cyan.opacity(0.6),
                quoteBackground: Color.cyan.opacity(0.06),
                bulletColor: Color.cyan,
                userBubbleGradient: [Color.blue.opacity(0.85), Color.indigo.opacity(0.9)],
                userTextColor: .white,
                assistantBackground: Color.clear,
                thinkingHeaderBackground: Color.indigo.opacity(0.08),
                thinkingBorder: Color.cyan.opacity(0.3)
            )

        case .cyberpunk:
            return MarkdownTheme(
                id: .cyberpunk,
                name: "Cyberpunk Neon",
                text: Color(white: 0.94),
                secondaryText: Color(white: 0.6),
                h1: Color.yellow,
                h2: Color.pink,
                h3: Color.cyan,
                boldText: Color.yellow,
                link: Color.cyan,
                inlineCodeText: Color.pink,
                inlineCodeBackground: Color.pink.opacity(0.15),
                codeBlockBackground: Color(red: 0.05, green: 0.05, blue: 0.1),
                codeBlockHeaderBackground: Color(red: 0.1, green: 0.08, blue: 0.15),
                codeBlockBorder: Color.pink.opacity(0.3),
                quoteBorder: Color.yellow.opacity(0.7),
                quoteBackground: Color.yellow.opacity(0.06),
                bulletColor: Color.pink,
                userBubbleGradient: [Color.pink.opacity(0.85), Color.purple.opacity(0.9)],
                userTextColor: .white,
                assistantBackground: Color.clear,
                thinkingHeaderBackground: Color.purple.opacity(0.12),
                thinkingBorder: Color.pink.opacity(0.4)
            )

        case .dracula:
            return MarkdownTheme(
                id: .dracula,
                name: "Dracula",
                text: Color(red: 0.95, green: 0.95, blue: 0.95),
                secondaryText: Color(red: 0.65, green: 0.65, blue: 0.75),
                h1: Color(red: 0.74, green: 0.57, blue: 0.97),
                h2: Color(red: 0.54, green: 0.89, blue: 0.98),
                h3: Color(red: 0.55, green: 0.98, blue: 0.67),
                boldText: Color(red: 1.0, green: 0.73, blue: 0.42),
                link: Color(red: 0.54, green: 0.89, blue: 0.98),
                inlineCodeText: Color(red: 0.55, green: 0.98, blue: 0.67),
                inlineCodeBackground: Color(red: 0.55, green: 0.98, blue: 0.67).opacity(0.12),
                codeBlockBackground: Color(red: 0.16, green: 0.17, blue: 0.24),
                codeBlockHeaderBackground: Color(red: 0.22, green: 0.24, blue: 0.32),
                codeBlockBorder: Color.white.opacity(0.08),
                quoteBorder: Color(red: 0.74, green: 0.57, blue: 0.97),
                quoteBackground: Color(red: 0.74, green: 0.57, blue: 0.97).opacity(0.08),
                bulletColor: Color(red: 0.54, green: 0.89, blue: 0.98),
                userBubbleGradient: [Color(red: 0.38, green: 0.31, blue: 0.62), Color(red: 0.26, green: 0.22, blue: 0.44)],
                userTextColor: .white,
                assistantBackground: Color.clear,
                thinkingHeaderBackground: Color(red: 0.38, green: 0.31, blue: 0.62).opacity(0.15),
                thinkingBorder: Color(red: 0.74, green: 0.57, blue: 0.97).opacity(0.35)
            )

        case .nord:
            return MarkdownTheme(
                id: .nord,
                name: "Nordic Frost",
                text: Color(red: 0.85, green: 0.87, blue: 0.91),
                secondaryText: Color(red: 0.58, green: 0.63, blue: 0.72),
                h1: Color(red: 0.53, green: 0.75, blue: 0.82),
                h2: Color(red: 0.56, green: 0.74, blue: 0.73),
                h3: Color(red: 0.92, green: 0.79, blue: 0.54),
                boldText: Color(red: 0.92, green: 0.93, blue: 0.96),
                link: Color(red: 0.53, green: 0.75, blue: 0.82),
                inlineCodeText: Color(red: 0.64, green: 0.75, blue: 0.55),
                inlineCodeBackground: Color(red: 0.64, green: 0.75, blue: 0.55).opacity(0.12),
                codeBlockBackground: Color(red: 0.18, green: 0.20, blue: 0.25),
                codeBlockHeaderBackground: Color(red: 0.23, green: 0.26, blue: 0.32),
                codeBlockBorder: Color.white.opacity(0.08),
                quoteBorder: Color(red: 0.53, green: 0.75, blue: 0.82),
                quoteBackground: Color(red: 0.53, green: 0.75, blue: 0.82).opacity(0.07),
                bulletColor: Color(red: 0.53, green: 0.75, blue: 0.82),
                userBubbleGradient: [Color(red: 0.37, green: 0.51, blue: 0.67), Color(red: 0.30, green: 0.40, blue: 0.55)],
                userTextColor: .white,
                assistantBackground: Color.clear,
                thinkingHeaderBackground: Color(red: 0.37, green: 0.51, blue: 0.67).opacity(0.12),
                thinkingBorder: Color(red: 0.53, green: 0.75, blue: 0.82).opacity(0.3)
            )

        case .monochrome:
            return MarkdownTheme(
                id: .monochrome,
                name: "Monochrome Studio",
                text: Color(white: 0.9),
                secondaryText: Color(white: 0.55),
                h1: Color.white,
                h2: Color(white: 0.95),
                h3: Color(white: 0.85),
                boldText: Color.white,
                link: Color(white: 0.95),
                inlineCodeText: Color.white,
                inlineCodeBackground: Color.white.opacity(0.1),
                codeBlockBackground: Color.black.opacity(0.6),
                codeBlockHeaderBackground: Color(white: 0.15),
                codeBlockBorder: Color.white.opacity(0.12),
                quoteBorder: Color.white.opacity(0.5),
                quoteBackground: Color.white.opacity(0.05),
                bulletColor: Color.white.opacity(0.7),
                userBubbleGradient: [Color(white: 0.22), Color(white: 0.16)],
                userTextColor: .white,
                assistantBackground: Color.clear,
                thinkingHeaderBackground: Color.white.opacity(0.06),
                thinkingBorder: Color.white.opacity(0.2)
            )
        }
    }
}
