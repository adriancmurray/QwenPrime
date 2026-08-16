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

    public init() {}

    public func checkHealth(baseURL: String = "http://127.0.0.1:8000/v1") async -> ServerStatus {
        guard let url = URL(string: "\(baseURL)/models") else {
            let status: ServerStatus = .disconnected(reason: "Invalid URL")
            self.currentStatus = status
            return status
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.0

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                let status: ServerStatus = .disconnected(reason: "Server returned non-200")
                self.currentStatus = status
                return status
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataArr = json["data"] as? [[String: Any]],
               let first = dataArr.first,
               let modelId = first["id"] as? String {
                let status: ServerStatus = .connected(model: modelId, latencyMs: elapsedMs)
                self.currentStatus = status
                return status
            }

            let status: ServerStatus = .connected(model: "qwen3.8-27b", latencyMs: elapsedMs)
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
        self.currentStatus = .connecting

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = [
            "-lc",
            "cd /Users/adrian/projects/local-eval-harness && uv run python -m harness.daemon.unified_server"
        ]
        try? proc.run()
        self.serverProcess = proc
    }

    public func stopEngine() {
        let killProc = Process()
        killProc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        killProc.arguments = ["-lc", "pkill -f unified_server || true"]
        try? killProc.run()
        killProc.waitUntilExit()

        serverProcess?.terminate()
        serverProcess = nil
        self.currentStatus = .disconnected(reason: "Stopped by user")
    }
}
