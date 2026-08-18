import Foundation
import QwenPrimeHarnessCore
import QwenPrimeHarnessProtocol

@main
struct QwenPrimeHarnessMain {
    static func main() async {
        do {
            guard let expectedCredential = ProcessInfo.processInfo.environment[
                "QWEN_PRIME_HARNESS_CREDENTIAL"
            ], !expectedCredential.isEmpty else {
                throw HarnessMainError.missingCredential
            }
            let input = try FileHandle.standardInput.read(upToCount: 1_048_577) ?? Data()
            guard !input.isEmpty, input.count <= 1_048_576 else {
                throw HarnessMainError.invalidInput
            }
            let request = try JSONDecoder().decode(
                HarnessRequest.self,
                from: input.trimmingTrailingNewlines()
            )
            let response = await HarnessEngine(
                expectedCredential: expectedCredential
            ).handle(request)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            var output = try encoder.encode(response)
            output.append(0x0A)
            try FileHandle.standardOutput.write(contentsOf: output)
        } catch {
            let message = "QwenPrimeHarness: \(error.localizedDescription)\n"
            try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
            Foundation.exit(64)
        }
    }
}

private enum HarnessMainError: Error, LocalizedError {
    case missingCredential
    case invalidInput

    var errorDescription: String? {
        switch self {
        case .missingCredential: "Missing harness credential."
        case .invalidInput: "Expected one bounded JSON request on standard input."
        }
    }
}

private extension Data {
    func trimmingTrailingNewlines() -> Data {
        var end = count
        while end > 0, self[index(startIndex, offsetBy: end - 1)] == 0x0A {
            end -= 1
        }
        return prefix(end)
    }
}
