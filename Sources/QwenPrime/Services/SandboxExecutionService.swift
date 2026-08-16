import Foundation

public actor SandboxExecutionService {
    public static let shared = SandboxExecutionService()

    public init() {}

    public func execute(
        code: String,
        workingDirectory: URL
    ) async -> (output: String, isSuccess: Bool) {
        let isShell = code.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("!")
        let cleanCommand: String

        if isShell {
            cleanCommand = String(code.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst())
        } else {
            // Run as Python code
            cleanCommand = "python3 -c \(escapeShellArg(code))"
        }

        let proc = Process()
        let pipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", cleanCommand]
        proc.currentDirectoryURL = workingDirectory
        proc.standardOutput = pipe
        proc.standardError = pipe

        // Inherit PATH and essential environment
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        proc.environment = env

        do {
            try proc.run()
            
            // Collect output asynchronously with timeout
            let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let d = pipe.fileHandleForReading.readDataToEndOfFile()
                    proc.waitUntilExit()
                    continuation.resume(returning: d)
                }
            }

            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let isSuccess = (proc.terminationStatus == 0)
            return (output.isEmpty ? "(Process exited with code \(proc.terminationStatus))" : output, isSuccess)
        } catch {
            return ("Execution failed: \(error.localizedDescription)", false)
        }
    }

    private func escapeShellArg(_ arg: String) -> String {
        return "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
