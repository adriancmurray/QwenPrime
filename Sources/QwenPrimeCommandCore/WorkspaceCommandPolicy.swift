import Foundation

public enum CommandPolicyError: Error, Sendable, Equatable, LocalizedError {
    case unsupportedCommand(String)
    case invalidArguments(String)
    case pathEscape(String)
    case limitsExceeded

    public var errorDescription: String? {
        switch self {
        case .unsupportedCommand(let command):
            return "Command is not allowed: \(command)"
        case .invalidArguments(let detail):
            return "Command arguments are not allowed: \(detail)"
        case .pathEscape(let path):
            return "Command path escapes the workspace: \(path)"
        case .limitsExceeded:
            return "Command argument limits were exceeded."
        }
    }
}

public enum WorkspaceCommandPolicy {
    public static func validate(command: String, arguments: [String]) throws {
        guard command.utf8.count <= 32,
              arguments.count <= 128,
              arguments.allSatisfy({ $0.utf8.count <= 4096 && !$0.utf8.contains(0) }) else {
            throw CommandPolicyError.limitsExceeded
        }
        try validateNoEscapingPaths(arguments)

        switch command {
        case "pwd":
            guard arguments.isEmpty else {
                throw CommandPolicyError.invalidArguments("pwd accepts no arguments")
            }
        case "ls":
            for argument in arguments {
                guard argument.hasPrefix("-"),
                      argument != "--",
                      !argument.dropFirst().isEmpty,
                      argument.dropFirst().allSatisfy({ "la1FGh".contains($0) }) else {
                    throw CommandPolicyError.invalidArguments(argument)
                }
            }
        default:
            throw CommandPolicyError.unsupportedCommand(command)
        }
    }

    public static func executableURL(for command: String) throws -> URL {
        let path: String
        switch command {
        case "pwd": path = "/bin/pwd"
        case "ls": path = "/bin/ls"
        default: throw CommandPolicyError.unsupportedCommand(command)
        }
        return URL(fileURLWithPath: path)
    }

    public static func sanitizedEnvironment() -> [String: String] {
        [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_PAGER": "cat",
            "PAGER": "cat",
            "HOME": "/nonexistent",
            "TMPDIR": NSTemporaryDirectory()
        ]
    }

    private static func validateNoEscapingPaths(_ arguments: [String]) throws {
        for argument in arguments {
            if argument.hasPrefix("/") {
                throw CommandPolicyError.pathEscape(argument)
            }
            let components = argument.split(separator: "/", omittingEmptySubsequences: false)
            if components.contains("..") {
                throw CommandPolicyError.pathEscape(argument)
            }
        }
    }
}
