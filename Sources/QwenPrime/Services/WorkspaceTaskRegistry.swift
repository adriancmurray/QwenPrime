import Foundation
import QwenPrimeCommandCore
import QwenPrimeCommandProtocol
import QwenPrimeHarnessProtocol

public struct WorkspaceTaskDescriptor: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let supportsFilter: Bool
}

public struct WorkspaceTaskCatalog: Codable, Equatable, Sendable {
    public let tasks: [WorkspaceTaskDescriptor]
    public let swiftPackages: [String]
    public let isTruncated: Bool
}

public struct WorkspaceHarnessInvocation: Equatable, Sendable {
    public let operation: HarnessOperation
    public let filter: String?
}

public enum WorkspaceTaskRegistry {
    private enum Task: String, CaseIterable {
        case swiftBuild = "swift_build"
        case swiftTest = "swift_test"

        var descriptor: WorkspaceTaskDescriptor {
            switch self {
            case .swiftBuild:
                WorkspaceTaskDescriptor(
                    id: rawValue,
                    title: "Swift Build",
                    description: "Build a self-contained Swift package offline.",
                    supportsFilter: false
                )
            case .swiftTest:
                WorkspaceTaskDescriptor(
                    id: rawValue,
                    title: "Swift Test",
                    description: "Run tests for a self-contained Swift package offline.",
                    supportsFilter: true
                )
            }
        }

        func arguments(filter: String?) throws -> [String] {
            switch self {
            case .swiftBuild:
                guard filter == nil else {
                    throw CommandPolicyError.invalidArguments(
                        "filter is valid only for swift_test"
                    )
                }
                return ["build"]
            case .swiftTest:
                return filter.map { ["test", "--filter", $0] } ?? ["test"]
            }
        }
    }

    public static let descriptors = Task.allCases.map(\.descriptor)

    public static func proposal(
        taskID: String,
        filter: String?,
        workingDirectory: String
    ) throws -> WorkspaceCommandProposal {
        guard let task = Task(rawValue: taskID) else {
            throw CommandPolicyError.invalidArguments("unsupported task")
        }
        let arguments = try task.arguments(filter: filter)
        try WorkspaceCommandPolicy.validate(command: "swift", arguments: arguments)
        return WorkspaceCommandProposal(
            command: "swift",
            arguments: arguments,
            workingDirectory: workingDirectory
        )
    }

    public static func harnessInvocation(
        for proposal: WorkspaceCommandProposal
    ) throws -> WorkspaceHarnessInvocation {
        guard proposal.command == "swift" else {
            throw CommandPolicyError.unsupportedCommand(proposal.command)
        }
        try WorkspaceCommandPolicy.validate(
            command: proposal.command,
            arguments: proposal.arguments
        )
        switch proposal.arguments {
        case ["build"]:
            return WorkspaceHarnessInvocation(operation: .swiftBuild, filter: nil)
        case ["test"]:
            return WorkspaceHarnessInvocation(operation: .swiftTest, filter: nil)
        case let arguments where arguments.count == 3
            && arguments[0] == "test"
            && arguments[1] == "--filter":
            return WorkspaceHarnessInvocation(operation: .swiftTest, filter: arguments[2])
        default:
            throw CommandPolicyError.invalidArguments("unsupported Swift task proposal")
        }
    }

    public static func catalog(
        in readService: ReadOnlyWorkspaceService
    ) async throws -> WorkspaceTaskCatalog {
        let search = try await readService.findFiles(
            query: "Package.swift",
            caseSensitive: true
        )
        let packages = search.matches.compactMap { match -> String? in
            guard URL(fileURLWithPath: match.relativePath).lastPathComponent == "Package.swift" else {
                return nil
            }
            return match.relativePath.split(separator: "/").dropLast()
                .joined(separator: "/")
        }
        return WorkspaceTaskCatalog(
            tasks: descriptors,
            swiftPackages: Array(Set(packages)).sorted(),
            isTruncated: search.isTruncated
        )
    }
}
