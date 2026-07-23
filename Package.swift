// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Notefy",
    platforms: [
        .macOS("14.0")
    ],
    products: [
        .executable(name: "notefy", targets: ["Notefy"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Notefy",
            dependencies: [],
            path: "Sources/Notefy"
        )
    ]
)
