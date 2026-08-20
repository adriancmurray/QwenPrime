import SwiftUI

/// Applies the shared native size for controls that participate in a form row.
/// This keeps macOS-managed field, picker, and button heights aligned without
/// hard-coding a height that would fight accessibility sizing.
public struct StandardFormControl: ViewModifier {
    public func body(content: Content) -> some View {
        content.controlSize(DesignTokens.Control.formSize)
    }
}

public extension View {
    func standardFormControl() -> some View {
        modifier(StandardFormControl())
    }
}
