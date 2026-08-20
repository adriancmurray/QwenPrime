import SwiftUI

extension View {
  public func appOperationErrorAlert(
    appState: AppState,
    scope: AppPresentationScope
  ) -> some View {
    modifier(
      AppOperationErrorAlertModifier(
        appState: appState,
        scope: scope
      )
    )
  }
}

private struct AppOperationErrorAlertModifier: ViewModifier {
  @Bindable var appState: AppState
  let scope: AppPresentationScope

  private var scopedPresentation: AppOperationErrorPresentation? {
    appState.presentedOperationError(in: scope)
  }

  func body(content: Content) -> some View {
    content.alert(
      scopedPresentation?.title ?? "Operation Failed",
      isPresented: Binding(
        get: { scopedPresentation != nil },
        set: { isPresented in
          appState.setOperationErrorPresented(
            isPresented,
            in: scope
          )
        }
      ),
      presenting: scopedPresentation
    ) { _ in
      Button("OK") {
        appState.setOperationErrorPresented(false, in: scope)
      }
    } message: { presentation in
      Text(presentation.message)
    }
  }
}
