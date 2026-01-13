// swift-tools-version:6.0
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
        .executable(name: "termqmcp", targets: ["termqmcp"]),
        .library(name: "TermQCore", targets: ["TermQCore"]),
        .library(name: "MCPServerLib", targets: ["MCPServerLib"])
    ],
    dependencies: [
        // Pinned to specific commit for build stability
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", revision: "5e9b2e31fc893021c7d081c4b52bf383fc654a80"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        // MCP Swift SDK for Model Context Protocol support
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.9.0")
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
        // MCP Server library (shared logic)
        .target(
            name: "MCPServerLib",
            dependencies: [
                "TermQCore",
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources/MCPServerLib"
        ),
        // MCP Server CLI binary
        .executableTarget(
            name: "termqmcp",
            dependencies: [
                "MCPServerLib",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/MCPServer-CLI"
        ),
        // Tests
        .testTarget(
            name: "TermQTests",
            dependencies: ["TermQCore"],
            path: "Tests/TermQTests"
        ),
        .testTarget(
            name: "MCPServerLibTests",
            dependencies: ["MCPServerLib", "TermQCore"],
            path: "Tests/MCPServerLibTests"
        )
    ]
)
