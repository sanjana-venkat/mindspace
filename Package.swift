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
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
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
                .product(name: "WhisperKit", package: "WhisperKit")
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
