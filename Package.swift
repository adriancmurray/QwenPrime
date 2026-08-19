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
        .library(
            name: "QwenPrimeCommandProtocol",
            targets: ["QwenPrimeCommandProtocol"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.3"
        ),
        .package(
            url: "https://github.com/modelcontextprotocol/swift-sdk.git",
            exact: "0.12.1"
        ),
        .package(
            url: "https://github.com/adriancmurray/swift-mcp-router.git",
            exact: "0.1.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "QwenPrime",
            dependencies: [
                "QwenPrimeCommandProtocol",
                "QwenPrimeCommandCore",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "SwiftMCPStore", package: "swift-mcp-router"),
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
            dependencies: ["QwenPrime"],
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
        )
    ]
)
