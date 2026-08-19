import Foundation
import QwenPrimeCommandProtocol

public actor SupervisedProcessRegistry {
    public typealias Operation = @Sendable () async -> CommandExecutionResponse

    private struct Entry {
        var snapshot: WorkspaceProcessSnapshot
        var task: Task<Void, Never>?
        let sequence: UInt64
    }

    private let maximumEntries: Int
    private var entries: [UUID: Entry] = [:]
    private var nextSequence: UInt64 = 0

    public init(maximumEntries: Int = 32) {
        self.maximumEntries = max(1, maximumEntries)
    }

    @discardableResult
    public func start(id: UUID, operation: @escaping Operation) -> WorkspaceProcessSnapshot {
        entries[id]?.task?.cancel()
        entries.removeValue(forKey: id)
        pruneIfNeeded()
        guard entries.count < maximumEntries else {
            return WorkspaceProcessSnapshot(
                id: id,
                state: .failed,
                result: nil,
                errorMessage: "The supervised process limit was reached."
            )
        }
        nextSequence &+= 1
        let snapshot = WorkspaceProcessSnapshot(
            id: id,
            state: .running,
            result: nil,
            errorMessage: nil
        )
        entries[id] = Entry(snapshot: snapshot, task: nil, sequence: nextSequence)
        entries[id]?.task = Task { [weak self] in
            let result = await operation()
            await self?.finish(id: id, result: result)
        }
        return snapshot
    }

    public func status(id: UUID) -> WorkspaceProcessSnapshot? {
        entries[id]?.snapshot
    }

    @discardableResult
    public func stop(id: UUID) -> WorkspaceProcessSnapshot? {
        guard var entry = entries[id] else { return nil }
        entry.task?.cancel()
        entry.task = nil
        entry.snapshot = WorkspaceProcessSnapshot(
            id: id,
            state: .stopped,
            result: entry.snapshot.result,
            errorMessage: nil
        )
        entries[id] = entry
        return entry.snapshot
    }

    private func finish(id: UUID, result: CommandExecutionResponse) {
        guard var entry = entries[id], entry.snapshot.state == .running else { return }
        let state: WorkspaceProcessState
        if result.cancelled {
            state = .stopped
        } else if result.isSuccess {
            state = .exited
        } else {
            state = .failed
        }
        entry.task = nil
        entry.snapshot = WorkspaceProcessSnapshot(
            id: id,
            state: state,
            result: result,
            errorMessage: result.errorMessage
        )
        entries[id] = entry
    }

    private func pruneIfNeeded() {
        guard entries.count >= maximumEntries else { return }
        let terminal = entries
            .filter { $0.value.snapshot.state != .running }
            .min { $0.value.sequence < $1.value.sequence }
        if let terminal {
            entries.removeValue(forKey: terminal.key)
        }
    }
}
