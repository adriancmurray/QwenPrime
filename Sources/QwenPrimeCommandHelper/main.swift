import Foundation
import QwenPrimeCommandProtocol

final class CommandServiceListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(
            with: QwenPrimeCommandServiceProtocol.self
        )
        newConnection.exportedObject = CommandService()
        newConnection.resume()
        return true
    }
}

let listener = NSXPCListener.service()
let delegate = CommandServiceListenerDelegate()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
