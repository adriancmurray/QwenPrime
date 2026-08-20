import SwiftUI

public enum DesignTokens {
    /// Semantic font roles for interface text. Keep point-based compatibility
    /// values below for older call sites while new UI uses these roles.
    public enum TextStyle {
        public static let micro = Font.system(
            .caption2,
            design: .default,
            weight: .medium
        )
        public static let caption2 = Font.caption2
        public static let caption = Font.caption
        public static let footnote = Font.footnote
        public static let subheadline = Font.subheadline
        public static let callout = Font.callout
        public static let body = Font.body
        public static let headline = Font.headline
        public static let title3 = Font.title3
        public static let title2 = Font.title2
        public static let title1 = Font.title
        public static let largeTitle = Font.largeTitle

        public static let caption2Monospaced = Font.system(
            .caption2,
            design: .monospaced
        )
        public static let captionMonospaced = Font.system(
            .caption,
            design: .monospaced
        )
        public static let footnoteMonospaced = Font.system(
            .footnote,
            design: .monospaced
        )
        public static let subheadlineMonospaced = Font.system(
            .subheadline,
            design: .monospaced
        )
        public static let calloutMonospaced = Font.system(
            .callout,
            design: .monospaced
        )
        public static let bodyMonospaced = Font.system(
            .body,
            design: .monospaced
        )
        public static let bodyLineSpacing: CGFloat = 3.5
        public static let codeLineSpacing: CGFloat = 4.0
        public static let headingLineSpacing: CGFloat = 2.0
    }

    // MARK: - Spacing Scale
    public enum Spacing {
        /// 2 pt - Micro gaps between badges or inline elements
        public static let xxs: CGFloat = 2
        /// 4 pt - Tight spacing between icons and text
        public static let xs: CGFloat = 4
        /// 6 pt - Standard compact gap between related items
        public static let sm: CGFloat = 6
        /// 8 pt - Standard container internal item spacing
        public static let md: CGFloat = 8
        /// 10 pt - Medium spacing for rows and cards
        public static let base: CGFloat = 10
        /// 12 pt - Header and section element spacing
        public static let lg: CGFloat = 12
        /// 14 pt - Message bubble and card gaps
        public static let xl: CGFloat = 14
        /// 16 pt - Container padding and major layout margins
        public static let xxl: CGFloat = 16
        /// 18 pt - Window edge margins and view gutters
        public static let gutter: CGFloat = 18
        /// 20 pt - Top-level view margins and empty state padding
        public static let section: CGFloat = 20
        /// 24 pt - Hero titles and banner offsets
        public static let hero: CGFloat = 24
        /// 32 pt - Large spacers and modal gaps
        public static let massive: CGFloat = 32
    }

    // MARK: - Corner Radius Scale
    public enum Radius {
        /// 3 pt - Micro badges and tags
        public static let xs: CGFloat = 3
        /// 5 pt - Action buttons and inline chips
        public static let sm: CGFloat = 5
        /// 6 pt - Text inputs and secondary cards
        public static let base: CGFloat = 6
        /// 8 pt - Standard message cards and disclosure boxes
        public static let md: CGFloat = 8
        /// 10 pt - Code blocks and tool execution cards
        public static let lg: CGFloat = 10
        /// 14 pt - User chat bubbles and primary popovers
        public static let xl: CGFloat = 14
        /// 18 pt - Input bars and floating overlays
        public static let xxl: CGFloat = 18
        /// 999 pt - Full circular pills and capsules
        public static let pill: CGFloat = 999
    }

    // MARK: - Opacity Scale
    public enum Opacity {
        /// 0.04 - Faint card backgrounds and unhovered states
        public static let faint: Double = 0.04
        /// 0.06 - Standard card and button background fills
        public static let subtle: Double = 0.06
        /// 0.12 - Hover states and active selections
        public static let hover: Double = 0.12
        /// 0.20 - Dividers and subtle container borders
        public static let divider: Double = 0.20
        /// 0.35 - Active borders and recessed backgrounds
        public static let prominent: Double = 0.35
        /// 0.45 - Disabled interactive controls
        public static let disabled: Double = 0.45
        /// 0.65 - Control backgrounds and dimmed overlays
        public static let strong: Double = 0.65
        /// 0.85 - Secondary text and prominent icons
        public static let high: Double = 0.85
    }

    // MARK: - Layout Dimensions
    public enum Layout {
        public static let maxContentWidth: CGFloat = 780
        public static let composerMaxWidth: CGFloat = 780
        public static let composerBottomMargin: CGFloat = 14
        public static let detailHeaderBackdropHeight: CGFloat = 72
        public static let toolbarControlHeight: CGFloat = 28
        public static let popoverActionRowHeight: CGFloat = 26
        public static let popoverActionIconWidth: CGFloat = 16
        /// A compact buffer between the top arrow and the first popover title.
        public static let popoverTopArrowClearance: CGFloat = 6
        public static let quickSettingsControlHeight: CGFloat = 52
        public static let quickSettingsActionRowHeight: CGFloat = 48
        public static let sidebarRowActionWidth: CGFloat = 24
        public static let sidebarRowMinHeight: CGFloat = 46
        public static let sidebarContentInset: CGFloat = 10
        public static let conversationActionPopoverWidth: CGFloat = 136
        public static let sidebarMinWidth: CGFloat = 220
        public static let sidebarIdealWidth: CGFloat = 260
        public static let sidebarMaxWidth: CGFloat = 320
        public static let quickSettingsPopoverWidth: CGFloat = 324
        public static let workspacePickerPopoverWidth: CGFloat = 184
        public static let runtimeProfilePickerPopoverWidth: CGFloat = 236
        public static let settingsWindowWidth: CGFloat = 680
        public static let settingsWindowHeight: CGFloat = 500
        public static let settingsTabHeight: CGFloat = 72
        public static let settingsTabIconHeight: CGFloat = 30
        public static let modalSheetWidth: CGFloat = 520
        public static let modalSheetHeight: CGFloat = 360
    }

    // MARK: - Native Control Sizing
    public enum Control {
        /// The semantic macOS size for text fields, menu pickers, and regular
        /// action buttons that appear together in a form row.
        public static let formSize: ControlSize = .regular
    }

    // MARK: - Animation Timings
    public enum AnimationCurve {
        public static let hover: Animation = .easeOut(duration: 0.12)
        public static let fast: Animation = .easeInOut(duration: 0.15)
        public static let standard: Animation = .easeInOut(duration: 0.22)
        public static let spring: Animation = .spring(response: 0.25, dampingFraction: 0.8)
        public static let presentation: Animation = .snappy(duration: 0.24, extraBounce: 0.03)
        public static let smoothScroll: Animation = .easeOut(duration: 0.12)
    }

    public enum Motion {
        public static let feedbackDuration: Duration = .seconds(2)

        public static func animation(
            _ animation: Animation,
            reduceMotion: Bool
        ) -> Animation? {
            reduceMotion ? nil : animation
        }
    }

    public enum Surface {
        public static let subtle = Color.primary.opacity(0.055)
        public static let opaqueFallback = Color(nsColor: .controlBackgroundColor)

        public static func adaptiveSubtle(
            contrast: ColorSchemeContrast,
            reduceTransparency: Bool
        ) -> Color {
            if reduceTransparency {
                return Color(nsColor: .controlBackgroundColor)
            }
            return Color.primary.opacity(contrast == .increased ? 0.12 : 0.055)
        }

        public static func adaptiveSelected(
            tint: Color = .primary,
            contrast: ColorSchemeContrast,
            reduceTransparency: Bool
        ) -> Color {
            if reduceTransparency {
                return tint.opacity(contrast == .increased ? 0.28 : 0.2)
            }
            return tint.opacity(contrast == .increased ? 0.24 : 0.14)
        }

        public static func recessed(
            contrast: ColorSchemeContrast,
            reduceTransparency: Bool
        ) -> Color {
            if reduceTransparency {
                return Color(nsColor: .textBackgroundColor)
            }
            return Color(nsColor: .textBackgroundColor)
                .opacity(contrast == .increased ? 0.94 : 0.78)
        }
    }

    public enum Stroke {
        public static let separator = Color.primary.opacity(0.11)

        public static func adaptiveSeparator(
            contrast: ColorSchemeContrast
        ) -> Color {
            Color.primary.opacity(contrast == .increased ? 0.32 : 0.11)
        }

        public static func adaptiveFocus(
            tint: Color = .primary,
            contrast: ColorSchemeContrast
        ) -> Color {
            tint.opacity(contrast == .increased ? 0.82 : 0.48)
        }

        public static func lineWidth(
            contrast: ColorSchemeContrast
        ) -> CGFloat {
            contrast == .increased ? 1.5 : 0.75
        }
    }

    public enum Syntax {
        public static func languageColor(for language: String) -> Color {
            switch language {
            case "python", "py":
                Color(red: 0.29, green: 0.56, blue: 0.85)
            case "swift":
                Color(red: 0.98, green: 0.40, blue: 0.18)
            case "rust", "rs":
                Color(red: 0.87, green: 0.35, blue: 0.22)
            case "javascript", "js", "typescript", "ts":
                Color(red: 0.95, green: 0.80, blue: 0.20)
            case "sh", "bash", "zsh", "shell":
                Color(red: 0.30, green: 0.80, blue: 0.45)
            case "json", "yaml", "yml", "toml":
                Color(red: 0.85, green: 0.65, blue: 0.30)
            case "html", "css":
                Color(red: 0.88, green: 0.42, blue: 0.65)
            case "c", "cpp", "c++", "h":
                Color(red: 0.38, green: 0.60, blue: 0.90)
            default:
                Status.activity
            }
        }
    }

    public enum Status {
        public static let success = Color(nsColor: .systemGreen)
        public static let warning = Color(nsColor: .systemOrange)
        public static let danger = Color(nsColor: .systemRed)
        public static let information = Color(nsColor: .systemBlue)
        public static let reasoning = Color(nsColor: .systemTeal)
        public static let activity = Color(nsColor: .systemTeal)
    }

    public enum Elevation {
        public static let floatingShadow = Color(nsColor: .shadowColor)
        public static let floatingRadius: CGFloat = 16
        public static let floatingOffset: CGFloat = 7
    }
}
