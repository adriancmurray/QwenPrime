import Foundation
import QwenPrimeCommandCore
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

    public func prepare(
        _ proposal: WorkspaceCommandProposal
    ) async throws -> WorkspaceCommandProposal {
        guard proposal.command == "git" else { return proposal }
        return WorkspaceCommandProposal(
            command: proposal.command,
            arguments: proposal.arguments,
            workingDirectory: proposal.workingDirectory,
            resourceGrants: try GitWorktreeMetadataResolver.requiredReadGrants(
                workspaceURL: workspaceURL
            )
        )
    }

    public func execute(
        _ proposal: WorkspaceCommandProposal
    ) async throws -> CommandExecutionResponse {
        let id = UUID()
        let request = try makeRequest(id: id, proposal: proposal, timeoutSeconds: 60)
        let data = try JSONEncoder().encode(request)
        let responseData = try await invoke(id: id) { service, reply in
            service.executeCommand(requestData: data, withReply: reply)
        }
        guard let response = try? JSONDecoder().decode(
            CommandExecutionResponse.self,
            from: responseData
        ), response.id == id else {
            throw WorkspaceCommandClientError.invalidResponse
        }
        return response
    }

    public func start(
        _ proposal: WorkspaceCommandProposal
    ) async throws -> WorkspaceProcessSnapshot {
        let id = UUID()
        let request = try makeRequest(
            id: id,
            proposal: proposal,
            timeoutSeconds: BoundedProcessRunner.maximumTimeoutSeconds
        )
        let data = try JSONEncoder().encode(request)
        return try await invokeSnapshot(id: id) { service, reply in
            service.startCommand(requestData: data, withReply: reply)
        }
    }

    public func status(id: UUID) async throws -> WorkspaceProcessSnapshot {
        try await invokeSnapshot(id: id) { service, reply in
            service.commandStatus(id: id, withReply: reply)
        }
    }

    public func stop(id: UUID) async throws -> WorkspaceProcessSnapshot {
        try await invokeSnapshot(id: id) { service, reply in
            service.stopCommand(id: id, withReply: reply)
        }
    }

    private func makeRequest(
        id: UUID,
        proposal: WorkspaceCommandProposal,
        timeoutSeconds: Double
    ) throws -> CommandExecutionRequest {
        let bookmark = try workspaceURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return CommandExecutionRequest(
            id: id,
            workspaceBookmark: bookmark,
            command: proposal.command,
            arguments: proposal.arguments,
            workingDirectory: proposal.workingDirectory,
            additionalReadBookmarks: try proposal.resourceGrants.map { grant in
                guard grant.access == .readOnly else {
                    throw WorkspaceCommandClientError.transportFailure(
                        "Unsupported resource grant."
                    )
                }
                return try URL(fileURLWithPath: grant.path, isDirectory: true)
                    .bookmarkData(
                        options: [],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
            },
            timeoutSeconds: timeoutSeconds,
            maxOutputBytes: 64 * 1024
        )
    }

    private func invokeSnapshot(
        id: UUID,
        operation: @escaping (QwenPrimeCommandServiceProtocol, @escaping @Sendable (Data) -> Void) -> Void
    ) async throws -> WorkspaceProcessSnapshot {
        let responseData = try await invoke(id: id, operation: operation)
        guard let snapshot = try? JSONDecoder().decode(
            WorkspaceProcessSnapshot.self,
            from: responseData
        ), snapshot.id == id else {
            throw WorkspaceCommandClientError.invalidResponse
        }
        return snapshot
    }

    private func invoke(
        id: UUID,
        operation: @escaping (QwenPrimeCommandServiceProtocol, @escaping @Sendable (Data) -> Void) -> Void
    ) async throws -> Data {
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
                    operation(service) { gate.resume(returning: $0) }
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
        return responseData
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
