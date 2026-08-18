import Foundation
import Testing
@testable import QwenPrimeHarnessCore

@Suite("Qwen Prime harness Seatbelt profile")
struct HarnessSeatbeltProfileTests {
    @Test("Profile denies network and limits reads and writes to system paths plus task root")
    func strictProfile() {
        let profile = HarnessSeatbeltProfile.make(
            taskRoot: URL(fileURLWithPath: "/Users/example/TaskRoot", isDirectory: true)
        )

        #expect(profile.contains("(deny default)"))
        #expect(!profile.contains("(allow network"))
        #expect(!profile.contains("(allow file-read*)"))
        #expect(profile.contains("(allow file-read* (subpath \"/System\"))"))
        #expect(profile.contains("(allow file-read* (subpath \"/Users/example/TaskRoot\"))"))
        #expect(profile.contains("(allow file-write* (subpath \"/Users/example/TaskRoot\"))"))
    }
}
