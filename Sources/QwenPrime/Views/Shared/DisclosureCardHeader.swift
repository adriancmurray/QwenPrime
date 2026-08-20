import SwiftUI

struct DisclosureCardPresentation: Equatable {
  let accessibilityLabel: String
  let accessibilityValue: String
  let accessibilityHint: String
  let isExpanded: Bool

  init(
    title: String,
    accessibilityLabel: String?,
    isExpanded: Bool
  ) {
    self.accessibilityLabel = accessibilityLabel ?? title
    self.isExpanded = isExpanded
    if isExpanded {
      accessibilityValue = String(localized: "Expanded")
      accessibilityHint = String(localized: "Collapse details")
    } else {
      accessibilityValue = String(localized: "Collapsed")
      accessibilityHint = String(localized: "Expand details")
    }
  }

  var toggledIsExpanded: Bool {
    !isExpanded
  }
}

/// A native, keyboard-focusable disclosure control shared by reasoning and
/// tool cards. Interactive accessories remain siblings, never nested buttons.
public struct DisclosureCardHeader<Metadata: View, Status: View, Accessory: View>: View {
  public let title: String
  public let accessibilityLabel: String
  public let systemImage: String
  public let tint: Color
  public let iconScale: CGFloat
  @Binding public var isExpanded: Bool
  @ViewBuilder public let metadata: Metadata
  @ViewBuilder public let status: Status
  @ViewBuilder public let accessory: Accessory

  @FocusState private var isFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  public init(
    title: String,
    accessibilityLabel: String? = nil,
    systemImage: String,
    tint: Color,
    iconScale: CGFloat = 1,
    isExpanded: Binding<Bool>,
    @ViewBuilder metadata: () -> Metadata,
    @ViewBuilder status: () -> Status,
    @ViewBuilder accessory: () -> Accessory
  ) {
    let presentation = DisclosureCardPresentation(
      title: title,
      accessibilityLabel: accessibilityLabel,
      isExpanded: isExpanded.wrappedValue
    )
    self.title = title
    self.accessibilityLabel = presentation.accessibilityLabel
    self.systemImage = systemImage
    self.tint = tint
    self.iconScale = iconScale
    self._isExpanded = isExpanded
    self.metadata = metadata()
    self.status = status()
    self.accessory = accessory()
  }

  public var body: some View {
    HStack(spacing: DesignTokens.Spacing.sm) {
      Button(action: toggle) {
        HStack(spacing: DesignTokens.Spacing.sm) {
          Image(systemName: systemImage)
            .font(DesignTokens.TextStyle.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .scaleEffect(iconScale)

          Text(title)
            .font(DesignTokens.TextStyle.subheadline.weight(.semibold))
            .foregroundStyle(.primary)

          metadata

          Spacer(minLength: DesignTokens.Spacing.sm)

          status

          Image(systemName: "chevron.down")
            .font(DesignTokens.TextStyle.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(presentation.isExpanded ? 180 : 0))
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focused($isFocused)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(presentation.accessibilityLabel)
      .accessibilityValue(presentation.accessibilityValue)
      .accessibilityHint(presentation.accessibilityHint)

      accessory
    }
    .padding(.horizontal, DesignTokens.Spacing.base)
    .padding(.vertical, DesignTokens.Spacing.sm)
    .background(
      DesignTokens.Surface.adaptiveSubtle(
        contrast: contrast,
        reduceTransparency: reduceTransparency
      )
    )
    .overlay(
      RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
        .stroke(
          isFocused
            ? DesignTokens.Stroke.adaptiveFocus(
              tint: tint,
              contrast: contrast
            )
            : Color.clear,
          lineWidth: DesignTokens.Stroke.lineWidth(contrast: contrast)
        )
    )

  }

  private var presentation: DisclosureCardPresentation {
    DisclosureCardPresentation(
      title: title,
      accessibilityLabel: accessibilityLabel,
      isExpanded: isExpanded
    )
  }

  private func toggle() {
    withAnimation(
      DesignTokens.Motion.animation(
        DesignTokens.AnimationCurve.spring,
        reduceMotion: reduceMotion
      )
    ) {
      isExpanded = presentation.toggledIsExpanded
    }
  }
}
