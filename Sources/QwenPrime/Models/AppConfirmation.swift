import Foundation
import SwiftUI

public enum AppConfirmationAction: Equatable, Sendable {
  case clearConversation(UUID)
  case deleteConversation(UUID)
  case deleteModelProfile(UUID)
  case deletePromptPreset(UUID)
  case removeMCPServer(String)
  case resetPromptPresets
}

public struct AppConfirmationRequest: Equatable, Identifiable, Sendable {
  public let id: UUID
  public let action: AppConfirmationAction
  public let title: String
  public let message: String
  public let confirmButtonTitle: String
  public let presentationScope: AppConfirmationPresentationScope

  public init(
    id: UUID = UUID(),
    action: AppConfirmationAction,
    title: String,
    message: String,
    confirmButtonTitle: String,
    presentationScope: AppConfirmationPresentationScope
  ) {
    self.id = id
    self.action = action
    self.title = title
    self.message = message
    self.confirmButtonTitle = confirmButtonTitle
    self.presentationScope = presentationScope
  }

  public func shouldPresent(
    in scope: AppConfirmationPresentationScope
  ) -> Bool {
    presentationScope == scope
  }
}

extension View {
  public func appConfirmationAlert(
    appState: AppState,
    scope: AppConfirmationPresentationScope
  ) -> some View {
    modifier(
      AppConfirmationAlertModifier(
        appState: appState,
        scope: scope
      )
    )
  }
}

private struct AppConfirmationAlertModifier: ViewModifier {
  @Bindable var appState: AppState
  let scope: AppConfirmationPresentationScope

  private var scopedRequest: AppConfirmationRequest? {
    appState.pendingConfirmation(in: scope)
  }

  func body(content: Content) -> some View {
    content.alert(
      scopedRequest?.title ?? "Confirm Action",
      isPresented: Binding(
        get: { scopedRequest != nil },
        set: { isPresented in
          guard !isPresented, let request = scopedRequest else { return }
          appState.setConfirmationPresented(
            false,
            id: request.id,
            in: scope
          )
        }
      ),
      presenting: scopedRequest
    ) { request in
      Button(request.confirmButtonTitle, role: .destructive) {
        appState.confirmPendingAction(
          id: request.id,
          in: scope
        )
      }
      .disabled(!appState.canConfirm(request))
      Button("Cancel", role: .cancel) {
        appState.dismissPendingConfirmation(id: request.id, in: scope)
      }
    } message: { request in
      Text(appState.confirmationMessage(for: request))
    }
  }
}
