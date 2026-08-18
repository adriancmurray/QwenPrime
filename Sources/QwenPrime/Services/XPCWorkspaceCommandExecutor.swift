import Foundation
import QwenPrimeCommandProtocol

public enum WorkspaceCommandClientError: Error, Sendable, Equatable, LocalizedError {
    case helperUnavailable
    case invalidResponse
    case transportFailure(String)

    public var errorDescription: String? {
        switch self {
        case .helperUnavailable:
            return "The sandboxed command helper is unavailable."
        case .invalidResponse:
            return "The sandboxed command helper returned an invalid response."
        case .transportFailure(let message):
            return "Sandboxed command transport failed: \(message)"
        }
    }
}

public actor XPCWorkspaceCommandExecutor: WorkspaceCommandExecuting {
    private let workspaceURL: URL
    private var connection: NSXPCConnection?

    public init(workspaceURL: URL) {
        self.workspaceURL = workspaceURL.standardizedFileURL
    }

    public func execute(
        _ proposal: WorkspaceCommandProposal
    ) async throws -> CommandExecutionResponse {
        let id = UUID()
        let bookmark = try workspaceURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let request = CommandExecutionRequest(
            id: id,
            workspaceBookmark: bookmark,
            command: proposal.command,
            arguments: proposal.arguments,
            workingDirectory: proposal.workingDirectory,
            timeoutSeconds: 30,
            maxOutputBytes: 64 * 1024
        )
        let data = try JSONEncoder().encode(request)
        let activeConnection = commandConnection()

        let responseData: Data
        do {
            responseData = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let gate = CommandReplyGate(continuation: continuation)
                    let proxy = activeConnection.remoteObjectProxyWithErrorHandler { error in
                        gate.resume(
                            throwing: WorkspaceCommandClientError.transportFailure(
                                error.localizedDescription
                            )
                        )
                    }
                    guard let service = proxy as? QwenPrimeCommandServiceProtocol else {
                        gate.resume(throwing: WorkspaceCommandClientError.helperUnavailable)
                        return
                    }
                    service.executeCommand(requestData: data) { response in
                        gate.resume(returning: response)
                    }
                }
            } onCancel: {
                Task { [weak self] in
                    await self?.cancel(id: id)
                }
            }
        } catch {
            activeConnection.invalidate()
            if connection === activeConnection {
                connection = nil
            }
            throw error
        }

        try Task.checkCancellation()
        guard let response = try? JSONDecoder().decode(
            CommandExecutionResponse.self,
            from: responseData
        ), response.id == id else {
            throw WorkspaceCommandClientError.invalidResponse
        }
        return response
    }

    private func commandConnection() -> NSXPCConnection {
        if let connection { return connection }
        let newConnection = NSXPCConnection(
            serviceName: QwenPrimeCommandServiceConstants.serviceName
        )
        newConnection.remoteObjectInterface = NSXPCInterface(
            with: QwenPrimeCommandServiceProtocol.self
        )
        newConnection.invalidationHandler = { [weak self] in
            Task { await self?.clearConnection() }
        }
        newConnection.interruptionHandler = { [weak self] in
            Task { await self?.clearConnection() }
        }
        newConnection.resume()
        connection = newConnection
        return newConnection
    }

    private func cancel(id: UUID) {
        guard let connection else { return }
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in }
        (proxy as? QwenPrimeCommandServiceProtocol)?.cancelCommand(id: id) { _ in }
    }

    private func clearConnection() {
        connection = nil
    }
}

private final class CommandReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?

    init(continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func resume(returning data: Data) {
        take()?.resume(returning: data)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Data, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let result = continuation
        continuation = nil
        return result
    }
}
