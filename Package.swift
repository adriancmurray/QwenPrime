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
        )
    ]
)
