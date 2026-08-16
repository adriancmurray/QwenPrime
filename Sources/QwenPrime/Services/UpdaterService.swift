import Foundation
import Sparkle

@MainActor
public final class UpdaterService {
    public static let shared = UpdaterService()

    private let controller: SPUStandardUpdaterController?

    public var isConfigured: Bool {
        controller != nil
    }

    public var canCheckForUpdates: Bool {
        controller != nil
    }

    private init(bundle: Bundle = .main) {
        let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String

        guard feedURL?.isEmpty == false, publicKey?.isEmpty == false else {
            controller = nil
            return
        }

        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    public func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
