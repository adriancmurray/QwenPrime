public enum RuntimeLifecycleAction: Sendable, Equatable {
  case start
  case stop
  case external

  public static func resolve(
    isConnected: Bool,
    isManaged: Bool
  ) -> RuntimeLifecycleAction {
    guard isConnected else { return .start }
    return isManaged ? .stop : .external
  }

  public var title: String {
    switch self {
    case .start: "Start Runtime"
    case .stop: "Stop Runtime"
    case .external: "External Runtime"
    }
  }
}
