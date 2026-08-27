// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Wave",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WaveCore", targets: ["WaveCore"]),
        .library(name: "WavePlatform", targets: ["WavePlatform"]),
        .executable(name: "Wave", targets: ["WaveApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.1.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples.git", from: "2.29.1"),
    ],
    targets: [
        // Pure logic. Foundation only — no AppKit, no hardware, no network.
        // Everything here is unit-testable; the platform seams are protocols.
        .target(
            name: "WaveCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // macOS integration: audio capture, hotkeys, text insertion, STT/LLM runtimes.
        .target(
            name: "WavePlatform",
            dependencies: [
                "WaveCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Menu bar, notch HUD, Settings, onboarding.
        .executableTarget(
            name: "WaveApp",
            dependencies: ["WaveCore", "WavePlatform"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WavePlatformTests",
            dependencies: ["WavePlatform"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WaveCoreTests",
            dependencies: ["WaveCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
