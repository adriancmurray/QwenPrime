import AppKit
import SwiftUI

public enum CopyFeedbackButtonPresentation: Sendable {
  case iconOnly
  case labeled(String)
}

protocol PresentationPasteboardWriting {
  func replaceContents(with value: String) -> Bool
}

struct SystemPresentationPasteboard: PresentationPasteboardWriting {
  let pasteboard: NSPasteboard

  func replaceContents(with value: String) -> Bool {
    pasteboard.clearContents()
    return pasteboard.setString(value, forType: .string)
  }
}

public enum PresentationClipboard {
  @MainActor
  @discardableResult
  public static func copy(_ value: String) -> Bool {
    copy(
      value,
      using: SystemPresentationPasteboard(pasteboard: .general)
    )
  }

  @MainActor
  static func copy(
    _ value: String,
    using pasteboard: some PresentationPasteboardWriting
  ) -> Bool {
    pasteboard.replaceContents(with: value)
  }
}

/// One cancellable clipboard action and feedback treatment for every renderer.
public struct CopyFeedbackButton: View {
  public let value: String
  public let label: String
  public let presentation: CopyFeedbackButtonPresentation
  public let isRevealed: Bool

  @State private var isCopied = false
  @State private var isHovered = false
  @State private var resetTask: Task<Void, Never>?
  @FocusState private var isFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  public init(
    value: String,
    label: String,
    presentation: CopyFeedbackButtonPresentation = .iconOnly,
    isRevealed: Bool = true
  ) {
    self.value = value
    self.label = label
    self.presentation = presentation
    self.isRevealed = isRevealed
  }

  public var body: some View {
    Button(action: copy) {
      content
        .foregroundStyle(isCopied ? DesignTokens.Status.success : .primary)
        .padding(.horizontal, horizontalPadding)
        .frame(minWidth: DesignTokens.Layout.toolbarControlHeight)
        .frame(height: DesignTokens.Layout.toolbarControlHeight)
        .background(
          backgroundColor,
          in: RoundedRectangle(
            cornerRadius: DesignTokens.Radius.sm,
            style: .continuous
          )
        )
    }
    .buttonStyle(.plain)
    .focused($isFocused)
    .opacity(isVisible ? 1 : 0)
    .allowsHitTesting(isVisible)
    .accessibilityHidden(!isVisible)
    .help(isCopied ? "Copied" : label)
    .accessibilityLabel(label)
    .accessibilityValue(isCopied ? "Copied" : "")
    .onHover { hovering in
      withAnimation(
        DesignTokens.Motion.animation(
          DesignTokens.AnimationCurve.hover,
          reduceMotion: reduceMotion
        )
      ) {
        isHovered = hovering
      }
    }
    .onDisappear {
      resetTask?.cancel()
      resetTask = nil
    }
  }

  @ViewBuilder
  private var content: some View {
    switch presentation {
    case .iconOnly:
      Image(systemName: isCopied ? "checkmark" : "square.on.square")
        .font(DesignTokens.TextStyle.caption.weight(.semibold))
    case .labeled(let title):
      HStack(spacing: DesignTokens.Spacing.xs) {
        Image(systemName: isCopied ? "checkmark" : "square.on.square")
        Text(isCopied ? "Copied" : title)
      }
      .font(DesignTokens.TextStyle.caption.weight(.medium))
    }
  }

  private var isVisible: Bool {
    isRevealed || isCopied || isFocused
  }

  private var horizontalPadding: CGFloat {
    switch presentation {
    case .iconOnly: DesignTokens.Spacing.xs
    case .labeled: DesignTokens.Spacing.md
    }
  }

  private var backgroundColor: Color {
    let isHighlighted = isHovered || isFocused || isCopied
    if isHighlighted {
      return DesignTokens.Surface.adaptiveSelected(
        contrast: contrast,
        reduceTransparency: reduceTransparency
      )
    }
    return DesignTokens.Surface.adaptiveSubtle(
      contrast: contrast,
      reduceTransparency: reduceTransparency
    )
  }

  @MainActor
  private func copy() {
    guard PresentationClipboard.copy(value) else { return }

    resetTask?.cancel()
    withAnimation(
      DesignTokens.Motion.animation(
        DesignTokens.AnimationCurve.fast,
        reduceMotion: reduceMotion
      )
    ) {
      isCopied = true
    }
    resetTask = Task { @MainActor in
      do {
        try await Task.sleep(for: DesignTokens.Motion.feedbackDuration)
      } catch {
        return
      }
      withAnimation(
        DesignTokens.Motion.animation(
          DesignTokens.AnimationCurve.fast,
          reduceMotion: reduceMotion
        )
      ) {
        isCopied = false
      }
    }
  }
}
