// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Evoo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Evoo", targets: ["Evoo"]),
        .executable(name: "evoo-cli", targets: ["evoo-cli"]),
    ],
    dependencies: [
        // Whisper (MIT) on CoreML — multilingual, incl. Hindi/Hinglish.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.0"),
        // Parakeet TDT (CC-BY-4.0 weights, Apache-2.0 runtime) on CoreML/ANE — fastest for English + EU languages.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.1"),
    ],
    targets: [
        // llama.cpp (MIT) prebuilt with Metal — runs the local refinement LLM.
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11155/llama-b11155-xcframework.zip",
            checksum: "1f157b625fe298aba099572a90aade102a1de31769ddfeff0e08330fb1296979"
        ),
        // Pure logic, no system frameworks beyond Foundation — unit-testable.
        .target(name: "EvooCore"),
        // Local LLM refinement (llama.cpp) + verified model downloads.
        .target(name: "EvooRefine", dependencies: ["EvooCore", "llama"]),
        // Speech engines (Parakeet, Whisper), number formatting, and the post-processing pipeline.
        .target(
            name: "EvooSpeech",
            dependencies: [
                "EvooCore",
                "EvooRefine",
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        // Menu-bar app.
        .executableTarget(
            name: "Evoo",
            dependencies: [
                "EvooCore",
                "EvooRefine",
                "EvooSpeech",
            ]
        ),
        // Dev tool: benchmark the pipeline from the terminal.
        .executableTarget(name: "evoo-cli", dependencies: ["EvooCore", "EvooRefine", "EvooSpeech"]),
        .testTarget(name: "EvooCoreTests", dependencies: ["EvooCore"]),
    ]
)
