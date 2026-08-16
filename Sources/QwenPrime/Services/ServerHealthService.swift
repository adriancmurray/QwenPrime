import Foundation

public enum ServerStatus: Equatable, Sendable {
    case connected(model: String, latencyMs: Double)
    case connecting
    case disconnected(reason: String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var displayText: String {
        switch self {
        case .connected(let model, let lat):
            return "\(model) (\(Int(lat))ms)"
        case .connecting:
            return "Starting Engine..."
        case .disconnected:
            return "Engine Stopped"
        }
    }
}

public actor ServerHealthService {
    public static let shared = ServerHealthService()

    private var currentStatus: ServerStatus = .connecting
    private var serverProcess: Process?
    private var serverLogHandle: FileHandle?

    public init() {}

    public func checkHealth(baseURL: String = "http://127.0.0.1:8000/v1") async -> ServerStatus {
        guard let url = URL(string: "\(baseURL)/engine") else {
            let status: ServerStatus = .disconnected(reason: "Invalid URL")
            self.currentStatus = status
            return status
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                let status: ServerStatus = .disconnected(reason: "Server returned non-200")
                self.currentStatus = status
                return status
            }

            if let identity = try? JSONDecoder().decode(QwenRuntimeIdentity.self, from: data),
               identity.isExpectedRuntime {
                let status: ServerStatus = .connected(
                    model: "Qwen3.8 27B + MTP 6-bit",
                    latencyMs: elapsedMs
                )
                self.currentStatus = status
                return status
            }

            let status: ServerStatus = .disconnected(reason: "Unexpected or unverified runtime")
            self.currentStatus = status
            return status
        } catch {
            let status: ServerStatus = .disconnected(reason: error.localizedDescription)
            self.currentStatus = status
            return status
        }
    }

    public func startEngine() {
        guard !currentStatus.isConnected else { return }
        guard serverProcess?.isRunning != true else { return }
        self.currentStatus = .connecting

        guard let executableURL = runtimeExecutableURL() else {
            self.currentStatus = .disconnected(
                reason: "Install qwen-prime-runtime or set QWEN_PRIME_RUNTIME_EXECUTABLE"
            )
            return
        }

        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = ["serve"]

        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/QwenPrime", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: logURL, withIntermediateDirectories: true)
            let fileURL = logURL.appendingPathComponent("runtime.log")
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            proc.standardOutput = handle
            proc.standardError = handle
            self.serverLogHandle = handle
        } catch {
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
        }

        do {
            try proc.run()
            self.serverProcess = proc
        } catch {
            self.currentStatus = .disconnected(reason: error.localizedDescription)
        }
    }

    public func stopEngine() {
        if let process = serverProcess, process.isRunning {
            process.terminate()
        }
        serverProcess = nil
        try? serverLogHandle?.close()
        serverLogHandle = nil
        self.currentStatus = .disconnected(reason: "Stopped by user")
    }

    public func doctorRuntime() -> RuntimeDoctorResult {
        guard let executableURL = runtimeExecutableURL() else {
            return RuntimeDoctorResult(
                isReady: false,
                message: "The Qwen Prime runtime is not installed in this app."
            )
        }

        let process = Process()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["doctor"]
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return RuntimeDoctorResult(
                isReady: process.terminationStatus == 0,
                message: message.isEmpty
                    ? "Runtime validation failed without diagnostic output."
                    : message
            )
        } catch {
            return RuntimeDoctorResult(isReady: false, message: error.localizedDescription)
        }
    }

    public func runtimeExecutableURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(
                "QwenPrimeRuntime/bin/qwen-prime-runtime"
            ),
            environment["QWEN_PRIME_RUNTIME_EXECUTABLE"].map(URL.init(fileURLWithPath:)),
            home.appendingPathComponent("Library/Application Support/QwenPrime/runtime/bin/qwen-prime-runtime"),
            home.appendingPathComponent(".local/bin/qwen-prime-runtime"),
            URL(fileURLWithPath: "/opt/homebrew/bin/qwen-prime-runtime"),
            URL(fileURLWithPath: "/usr/local/bin/qwen-prime-runtime"),
        ].compactMap { $0 }

        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }
}
