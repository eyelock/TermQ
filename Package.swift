// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TermQ",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TermQ", targets: ["TermQ"]),
        .executable(name: "termq", targets: ["termq-cli"]),
        .library(name: "TermQCore", targets: ["TermQCore"])
    ],
    dependencies: [
        // Pinned to specific commit for build stability
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", revision: "5e9b2e31fc893021c7d081c4b52bf383fc654a80"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0")
    ],
    targets: [
        // Core library with models (testable)
        .target(
            name: "TermQCore",
            dependencies: [],
            path: "Sources/TermQCore"
        ),
        // Main app
        .executableTarget(
            name: "TermQ",
            dependencies: [
                "TermQCore",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/TermQ",
            resources: [
                .copy("Resources/Help"),
                .process("Resources/en.lproj")
            ]
        ),
        // CLI tool
        .executableTarget(
            name: "termq-cli",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/termq-cli"
        ),
        // Tests
        .testTarget(
            name: "TermQTests",
            dependencies: ["TermQCore"],
            path: "Tests/TermQTests"
        )
    ]
)
