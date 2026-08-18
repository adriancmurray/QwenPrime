import Foundation
import Darwin

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

    private let session: URLSession
    private var currentStatus: ServerStatus = .connecting
    private var verifiedIdentity: QwenRuntimeIdentity?
    private var verifiedBaseURL: String?
    private var isEndpointOccupied: Bool = false
    private var serverProcess: Process?
    private var serverLogHandle: FileHandle?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func currentIdentity() -> QwenRuntimeIdentity? {
        verifiedIdentity
    }

    public func currentIdentity(for baseURL: String) -> QwenRuntimeIdentity? {
        guard verifiedBaseURL == baseURL else { return nil }
        return verifiedIdentity
    }

    public func isManagedServerRunning() -> Bool {
        serverProcess?.isRunning == true
    }

    public func endpointIsOccupied() -> Bool {
        isEndpointOccupied
    }

    public func checkHealth(baseURL: String = "http://127.0.0.1:8000/v1") async -> ServerStatus {
        guard let url = URL(string: "\(baseURL)/engine") else {
            self.verifiedIdentity = nil
            self.verifiedBaseURL = nil
            self.isEndpointOccupied = false
            let status: ServerStatus = .disconnected(reason: "Invalid URL")
            self.currentStatus = status
            return status
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (data, response) = try await session.data(for: request)
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

            guard let httpResponse = response as? HTTPURLResponse else {
                self.verifiedIdentity = nil
                self.verifiedBaseURL = nil
                self.isEndpointOccupied = false
                let status: ServerStatus = .disconnected(reason: "Invalid server response")
                self.currentStatus = status
                return status
            }

            self.isEndpointOccupied = true

            guard (200...299).contains(httpResponse.statusCode) else {
                self.verifiedIdentity = nil
                self.verifiedBaseURL = nil
                let status: ServerStatus = .disconnected(reason: "Server returned non-200 (HTTP \(httpResponse.statusCode))")
                self.currentStatus = status
                return status
            }

            if let identity = try? JSONDecoder().decode(QwenRuntimeIdentity.self, from: data) {
                if identity.isExpectedRuntime {
                    self.verifiedIdentity = identity
                    self.verifiedBaseURL = baseURL
                    let modelLabel = identity.quantizationSummary.isEmpty
                        ? "Qwen3.8 27B + MTP"
                        : "Qwen3.8 27B · \(identity.quantizationSummary)"
                    let status: ServerStatus = .connected(
                        model: modelLabel,
                        latencyMs: elapsedMs
                    )
                    self.currentStatus = status
                    return status
                } else if !identity.warmupComplete && identity.runtimeId == "qwen38-native-mtp-v2" {
                    self.verifiedIdentity = nil
                    self.verifiedBaseURL = nil
                    let status: ServerStatus = .connecting
                    self.currentStatus = status
                    return status
                } else {
                    self.verifiedIdentity = nil
                    self.verifiedBaseURL = nil
                    let status: ServerStatus = .disconnected(reason: "Incompatible runtime (\(identity.runtimeId))")
                    self.currentStatus = status
                    return status
                }
            }

            self.verifiedIdentity = nil
            self.verifiedBaseURL = nil
            let status: ServerStatus = .disconnected(reason: "Unexpected or unverified runtime")
            self.currentStatus = status
            return status
        } catch {
            self.verifiedIdentity = nil
            self.verifiedBaseURL = nil
            self.isEndpointOccupied = false
            let status: ServerStatus = .disconnected(reason: error.localizedDescription)
            self.currentStatus = status
            return status
        }
    }

    public func startEngine() {
        guard !currentStatus.isConnected else { return }
        guard serverProcess?.isRunning != true else { return }
        guard !isEndpointOccupied else {
            self.currentStatus = .disconnected(
                reason: "Endpoint is occupied by an external server or warming process"
            )
            return
        }

        self.verifiedIdentity = nil
        self.verifiedBaseURL = nil
        self.currentStatus = .connecting

        guard let executableURL = runtimeExecutableURL() else {
            self.verifiedIdentity = nil
            self.verifiedBaseURL = nil
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
            self.verifiedIdentity = nil
            self.verifiedBaseURL = nil
            self.currentStatus = .disconnected(reason: error.localizedDescription)
        }
    }

    public func stopEngine() {
        guard let process = serverProcess, process.isRunning else {
            self.currentStatus = .disconnected(
                reason: "The active runtime is external and is not managed by this app"
            )
            return
        }
        guard terminateManagedProcess(process) else {
            self.currentStatus = .disconnected(
                reason: "The managed runtime did not terminate cleanly"
            )
            return
        }
        serverProcess = nil
        try? serverLogHandle?.close()
        serverLogHandle = nil
        self.verifiedIdentity = nil
        self.verifiedBaseURL = nil
        self.isEndpointOccupied = false
        self.currentStatus = .disconnected(reason: "Stopped by user")
    }

    private func terminateManagedProcess(
        _ process: Process,
        gracefulTimeout: TimeInterval = 5,
        forcedTimeout: TimeInterval = 2
    ) -> Bool {
        process.terminate()
        var deadline = Date().addingTimeInterval(gracefulTimeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            deadline = Date().addingTimeInterval(forcedTimeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        return !process.isRunning
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
