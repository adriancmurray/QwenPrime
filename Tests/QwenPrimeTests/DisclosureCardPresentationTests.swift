import Testing

@testable import QwenPrime

@Suite("Disclosure card presentation")
struct DisclosureCardPresentationTests {
  @Test("Collapsed disclosures use their title and advertise expansion")
  func collapsedDefaultPresentation() {
    let presentation = DisclosureCardPresentation(
      title: "Thinking",
      accessibilityLabel: nil,
      isExpanded: false
    )

    #expect(presentation.accessibilityLabel == "Thinking")
    #expect(presentation.accessibilityValue == "Collapsed")
    #expect(presentation.accessibilityHint == "Expand details")
    #expect(presentation.toggledIsExpanded)
  }

  @Test("Expanded disclosures keep a custom label and advertise collapse")
  func expandedCustomPresentation() {
    let presentation = DisclosureCardPresentation(
      title: "Tool",
      accessibilityLabel: "Workspace read details",
      isExpanded: true
    )

    #expect(presentation.accessibilityLabel == "Workspace read details")
    #expect(presentation.accessibilityValue == "Expanded")
    #expect(presentation.accessibilityHint == "Collapse details")
    #expect(!presentation.toggledIsExpanded)
  }
}
