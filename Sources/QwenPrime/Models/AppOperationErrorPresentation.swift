import Foundation

public enum AppOperationErrorPresentation: Equatable, Sendable {
  public enum Kind: String, Equatable, Sendable {
    case workspaceAuthorization
    case runtimeProfilePersistence
    case conversationExport
  }

  case workspaceAuthorization(message: String)
  case runtimeProfilePersistence
  case conversationExport

  public var presentationScope: AppPresentationScope {
    switch self {
    case .runtimeProfilePersistence:
      .settingsWindow
    case .workspaceAuthorization, .conversationExport:
      .mainWindow
    }
  }

  public var kind: Kind {
    switch self {
    case .workspaceAuthorization:
      .workspaceAuthorization
    case .runtimeProfilePersistence:
      .runtimeProfilePersistence
    case .conversationExport:
      .conversationExport
    }
  }

  public var title: String {
    switch self {
    case .workspaceAuthorization:
      "Workspace Access Failed"
    case .runtimeProfilePersistence:
      "Model Profile Could Not Be Saved"
    case .conversationExport:
      "Export Failed"
    }
  }

  public var message: String {
    switch self {
    case .workspaceAuthorization(let message):
      message
    case .runtimeProfilePersistence:
      "Your model profile changes were not saved. Please try again."
    case .conversationExport:
      "The conversation could not be exported. Choose another location and try again."
    }
  }
}
