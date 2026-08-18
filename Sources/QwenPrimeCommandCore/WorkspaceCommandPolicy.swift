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
    private static let allowedGitSubcommands: Set<String> = [
        "log", "rev-parse"
    ]

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
        case "git":
            try validateGit(arguments)
        default:
            throw CommandPolicyError.unsupportedCommand(command)
        }
    }

    public static func executableURL(for command: String) throws -> URL {
        let path: String
        switch command {
        case "pwd": path = "/bin/pwd"
        case "ls": path = "/bin/ls"
        case "git":
            let candidates = [
                "/Library/Developer/CommandLineTools/usr/bin/git",
                "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
                "/Applications/Xcode-beta.app/Contents/Developer/usr/bin/git"
            ]
            guard let installed = candidates.first(where: {
                FileManager.default.isExecutableFile(atPath: $0)
            }) else {
                throw CommandPolicyError.unsupportedCommand(
                    "git requires Xcode Command Line Tools"
                )
            }
            path = installed
        default: throw CommandPolicyError.unsupportedCommand(command)
        }
        return URL(fileURLWithPath: path)
    }

    public static func launchArguments(
        command: String,
        arguments: [String]
    ) throws -> [String] {
        try validate(command: command, arguments: arguments)
        guard command == "git" else { return arguments }

        let hardening = [
            "-c", "core.fsmonitor=false",
            "-c", "core.hooksPath=/dev/null",
            "-c", "core.pager=cat"
        ]
        guard let subcommand = arguments.first else {
            throw CommandPolicyError.invalidArguments("missing git subcommand")
        }
        var result = hardening + arguments
        if subcommand == "log" {
            result.insert(contentsOf: ["--no-patch", "--no-show-signature"], at: hardening.count + 1)
        }
        return result
    }

    public static func sanitizedEnvironment() -> [String: String] {
        [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_PAGER": "cat",
            "PAGER": "cat",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_OPTIONAL_LOCKS": "0",
            "HOME": "/nonexistent",
            "TMPDIR": NSTemporaryDirectory()
        ]
    }

    private static func validateGit(_ arguments: [String]) throws {
        guard let subcommand = arguments.first,
              allowedGitSubcommands.contains(subcommand) else {
            throw CommandPolicyError.invalidArguments("unsupported git subcommand")
        }
        switch subcommand {
        case "rev-parse":
            let allowedForms: Set<[String]> = [
                ["rev-parse", "--show-toplevel"],
                ["rev-parse", "--is-inside-work-tree"],
                ["rev-parse", "--show-prefix"],
                ["rev-parse", "--git-dir"],
                ["rev-parse", "HEAD"],
                ["rev-parse", "--abbrev-ref", "HEAD"]
            ]
            guard allowedForms.contains(arguments) else {
                throw CommandPolicyError.invalidArguments("unsupported rev-parse form")
            }
        case "log":
            try validateGitLog(arguments)
        default:
            throw CommandPolicyError.invalidArguments("unsupported git subcommand")
        }
    }

    private static func validateGitLog(_ arguments: [String]) throws {
        var index = 1
        var expectsCount = false
        while index < arguments.count {
            let argument = arguments[index]
            if expectsCount {
                guard let count = Int(argument), (1...100).contains(count) else {
                    throw CommandPolicyError.invalidArguments("invalid git log count")
                }
                expectsCount = false
            } else if argument == "-n" {
                expectsCount = true
            } else if argument.hasPrefix("--max-count=") {
                let value = String(argument.dropFirst("--max-count=".count))
                guard let count = Int(value), (1...100).contains(count) else {
                    throw CommandPolicyError.invalidArguments("invalid git log count")
                }
            } else if !["--oneline", "--decorate=no", "--all", "HEAD"].contains(argument) {
                throw CommandPolicyError.invalidArguments("unsupported git log option")
            }
            index += 1
        }
        guard !expectsCount else {
            throw CommandPolicyError.invalidArguments("missing git log count")
        }
    }

    private static func validateNoEscapingPaths(_ arguments: [String]) throws {
        for argument in arguments {
            let values = [argument, argument.split(separator: "=", maxSplits: 1).last.map(String.init) ?? argument]
            for value in values {
                if value.hasPrefix("/") {
                    throw CommandPolicyError.pathEscape(argument)
                }
                let components = value.split(separator: "/", omittingEmptySubsequences: false)
                if components.contains("..") {
                    throw CommandPolicyError.pathEscape(argument)
                }
            }
        }
    }
}
