// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Notefy",
    platforms: [
        .macOS("14.0")
    ],
    products: [
        .executable(name: "notefy", targets: ["Notefy"]),
        .executable(name: "notefy-app", targets: ["NotefyApp"])
    ],
    dependencies: [
        // Parakeet does all the on-device speech now — the live transcript and
        // the finished one. WhisperKit used to do the second job; carrying two
        // speech models meant two downloads and two sets of weights in memory
        // for one task.
        // Vendored under ThirdParty: upstream ships a 49MB prebuilt Rust
        // xcframework this app never calls, and a build should not depend on
        // a binary artifact download. See ThirdParty/FluidAudio/Package.swift.
        .package(path: "ThirdParty/FluidAudio")
    ],
    targets: [
        .target(
            name: "NotefyCore",
            dependencies: [],
            path: "Sources/NotefyCore"
        ),
        .executableTarget(
            name: "Notefy",
            dependencies: ["NotefyCore"],
            path: "Sources/Notefy"
        ),
        .executableTarget(
            name: "NotefyApp",
            dependencies: [
                "NotefyCore",
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/NotefyApp",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "NotefyCoreTests",
            dependencies: ["NotefyCore"],
            path: "Tests/NotefyCoreTests"
        )
    ]
)
