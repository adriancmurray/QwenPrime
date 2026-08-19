import Foundation

public enum CommandPolicyError: Error, Sendable, Equatable, LocalizedError {
    case unsupportedCommand(String)
    case invalidArguments(String)
    case pathEscape(String)
    case limitsExceeded

    public var errorDescription: String? {
        switch self {
        case .unsupportedCommand(let command):
            return "Command is not available: \(command)"
        case .invalidArguments(let detail):
            return "Command arguments are invalid: \(detail)"
        case .pathEscape(let path):
            return "Command path escapes the workspace: \(path)"
        case .limitsExceeded:
            return "Command argument limits were exceeded."
        }
    }
}

public enum WorkspaceCommandPolicy {
    private static let searchDirectories = [
        "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        "/Library/Developer/CommandLineTools/usr/bin",
        "/Applications/Xcode.app/Contents/Developer/usr/bin",
        "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin",
        "/Applications/Xcode-beta.app/Contents/Developer/usr/bin",
        "/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"
    ]

    public static func validate(command: String, arguments: [String]) throws {
        guard !command.isEmpty,
              command.utf8.count <= 1024,
              !command.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              arguments.count <= 128,
              arguments.allSatisfy({ $0.utf8.count <= 4096 && !$0.utf8.contains(0) }) else {
            throw CommandPolicyError.limitsExceeded
        }
        guard !command.hasPrefix("/") else {
            throw CommandPolicyError.pathEscape(command)
        }
        if command.contains("/") {
            let components = command.split(separator: "/", omittingEmptySubsequences: false)
            guard !components.contains(".."), components.last?.isEmpty == false else {
                throw CommandPolicyError.pathEscape(command)
            }
        }
    }

    public static func executableURL(for command: String) throws -> URL {
        try validate(command: command, arguments: [])
        guard !command.contains("/") else {
            throw CommandPolicyError.invalidArguments(
                "workspace-relative executables require a working directory"
            )
        }
        guard let installed = searchDirectories.lazy
            .map({ URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent(command) })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw CommandPolicyError.unsupportedCommand(command)
        }
        return installed
    }

    public static func executableURL(
        for command: String,
        workingDirectory: URL,
        workspaceRoot: URL
    ) throws -> URL {
        try validate(command: command, arguments: [])
        guard command.contains("/") else {
            return try executableURL(for: command)
        }
        let root = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        let directory = workingDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard contains(directory, within: root) else {
            throw CommandPolicyError.pathEscape(workingDirectory.path)
        }
        let candidate = directory
            .appendingPathComponent(command)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard contains(candidate, within: root) else {
            throw CommandPolicyError.pathEscape(command)
        }
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else {
            throw CommandPolicyError.unsupportedCommand(command)
        }
        return candidate
    }

    public static func sanitizedEnvironment() -> [String: String] {
        let temporaryDirectory = NSTemporaryDirectory()
        return [
            "PATH": searchDirectories.joined(separator: ":"),
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            "HOME": temporaryDirectory,
            "CFFIXED_USER_HOME": temporaryDirectory,
            "TMPDIR": temporaryDirectory,
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_PAGER": "cat",
            "PAGER": "cat"
        ]
    }

    private static func contains(_ candidate: URL, within root: URL) -> Bool {
        candidate.path == root.path || candidate.path.hasPrefix(root.path + "/")
    }
}
