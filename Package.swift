// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QwenPrime",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "QwenPrime",
            targets: ["QwenPrime"]
        ),
        .executable(
            name: "QwenPrimeCommandHelper",
            targets: ["QwenPrimeCommandHelper"]
        ),
        .executable(
            name: "QwenPrimeHarness",
            targets: ["QwenPrimeHarness"]
        ),
        .library(
            name: "QwenPrimeCommandProtocol",
            targets: ["QwenPrimeCommandProtocol"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.3"
        )
    ],
    targets: [
        .executableTarget(
            name: "QwenPrime",
            dependencies: [
                "QwenPrimeCommandProtocol",
                "QwenPrimeCommandCore",
                "QwenPrimeHarnessProtocol",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/QwenPrime",
            resources: [
                .process("../../Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "QwenPrimeCommandProtocol",
            path: "Sources/QwenPrimeCommandProtocol",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "QwenPrimeCommandCore",
            dependencies: ["QwenPrimeCommandProtocol"],
            path: "Sources/QwenPrimeCommandCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "QwenPrimeHarnessProtocol",
            path: "Sources/QwenPrimeHarnessProtocol",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "QwenPrimeHarnessCore",
            dependencies: [
                "QwenPrimeHarnessProtocol",
                "QwenPrimeCommandProtocol",
                "QwenPrimeCommandCore"
            ],
            path: "Sources/QwenPrimeHarnessCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "QwenPrimeHarness",
            dependencies: ["QwenPrimeHarnessProtocol", "QwenPrimeHarnessCore"],
            path: "Sources/QwenPrimeHarness",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "QwenPrimeCommandHelper",
            dependencies: ["QwenPrimeCommandProtocol", "QwenPrimeCommandCore"],
            path: "Sources/QwenPrimeCommandHelper",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "QwenPrimeTests",
            dependencies: ["QwenPrime", "QwenPrimeHarnessProtocol"],
            path: "Tests/QwenPrimeTests",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@loader_path/../../.."
                ])
            ]
        ),
        .testTarget(
            name: "QwenPrimeCommandCoreTests",
            dependencies: ["QwenPrimeCommandProtocol", "QwenPrimeCommandCore"],
            path: "Tests/QwenPrimeCommandCoreTests"
        ),
        .testTarget(
            name: "QwenPrimeHarnessCoreTests",
            dependencies: ["QwenPrimeHarnessProtocol", "QwenPrimeHarnessCore"],
            path: "Tests/QwenPrimeHarnessCoreTests"
        )
    ]
)
