import SwiftUI

public enum DesignTokens {
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

    // MARK: - Typography Scale
    public enum Typography {
        /// 8.5 pt - Micro badge icons and superscript stats
        public static let micro: CGFloat = 8.5
        /// 9.5 pt - Timestamps, token counters, and shortcut hints
        public static let caption2: CGFloat = 9.5
        public static let caption: CGFloat = 10.5
        /// 10.5 pt - Secondary stats, monospace chips, and badges
        public static let footnote: CGFloat = 10.5
        /// 11.5 pt - Accordion titles, tool labels, and secondary UI
        public static let subheadline: CGFloat = 11.5
        /// 12.5 pt - Code blocks, prompts, and sidebar row titles
        public static let callout: CGFloat = 12.5
        /// 13.5 pt - Standard message body text and input text
        public static let body: CGFloat = 13.5
        /// 14.5 pt - Section headers and modal titles
        public static let headline: CGFloat = 14.5
        /// 16.0 pt - Subsection headers and large labels
        public static let title3: CGFloat = 16.0
        /// 18.0 pt - Markdown H1 headers and dialog titles
        public static let title2: CGFloat = 18.0
        /// 22.0 pt - Hero view titles and brand headers
        public static let title1: CGFloat = 22.0

        // Line Spacings
        public static let lineSpacingBody: CGFloat = 3.5
        public static let lineSpacingCode: CGFloat = 4.0
        public static let lineSpacingHeading: CGFloat = 2.0
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
        public static let composerScrollClearance: CGFloat = 148
        public static let toolbarControlHeight: CGFloat = 28
        public static let sidebarRowActionWidth: CGFloat = 24
        public static let sidebarRowMinHeight: CGFloat = 46
        public static let sidebarMinWidth: CGFloat = 220
        public static let sidebarIdealWidth: CGFloat = 260
        public static let sidebarMaxWidth: CGFloat = 320
        public static let quickSettingsPopoverWidth: CGFloat = 324
        public static let settingsWindowWidth: CGFloat = 680
        public static let settingsWindowHeight: CGFloat = 500
        public static let modalSheetWidth: CGFloat = 520
        public static let modalSheetHeight: CGFloat = 360
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

    public enum Surface {
        public static let subtle = Color.primary.opacity(0.055)
        public static let selected = Color.accentColor.opacity(0.14)
        public static let opaqueFallback = Color(nsColor: .controlBackgroundColor)
    }

    public enum Stroke {
        public static let separator = Color.primary.opacity(0.11)
        public static let focus = Color.accentColor.opacity(0.48)
    }
}
