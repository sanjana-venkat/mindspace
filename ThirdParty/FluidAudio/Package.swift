// swift-tools-version: 6.0
import PackageDescription

// FluidAudio v0.15.7 (github.com/FluidInference/FluidAudio), vendored.
//
// Two changes from upstream, both subtractions:
//
//  1. The `NemoTextProcessing` binary target is gone. It is a 49MB prebuilt
//     Rust xcframework for NeMo text normalisation, which this app does not
//     use — the library guards every reference with
//     `#if canImport(CNemoTextProcessing)`, so it compiles without it.
//  2. The CLI and test targets are gone; only the library is needed.
//
// Vendored rather than fetched so a build never depends on a binary artifact
// download, and so the app ships only the speech recognition it actually runs.
let package = Package(
    name: "FluidAudio",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "FluidAudio", targets: ["FluidAudio"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FluidAudio",
            dependencies: [
                "FastClusterWrapper",
                "MachTaskSelfWrapper",
            ],
            path: "Sources/FluidAudio",
            exclude: ["ASR/Parakeet/Unified/benchmark.md"],
            resources: [
                .process("TTS/LuxTts/G2p/Resources")
            ]
        ),
        .target(
            name: "FastClusterWrapper",
            path: "Sources/FastClusterWrapper",
            publicHeadersPath: "include"
        ),
        .target(
            name: "MachTaskSelfWrapper",
            path: "Sources/MachTaskSelfWrapper",
            publicHeadersPath: "include"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
