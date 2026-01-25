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
        .executable(name: "termqcli", targets: ["termq-cli"]),
        .executable(name: "termqmcp", targets: ["termqmcp"]),
        .library(name: "TermQCore", targets: ["TermQCore"]),
        .library(name: "TermQShared", targets: ["TermQShared"]),
        .library(name: "MCPServerLib", targets: ["MCPServerLib"])
    ],
    dependencies: [
        // Pinned to specific commit for build stability
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", revision: "5e9b2e31fc893021c7d081c4b52bf383fc654a80"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        // MCP Swift SDK for Model Context Protocol support
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.9.0"),
        // Sparkle for auto-updates
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        // Core library with models (testable)
        .target(
            name: "TermQCore",
            dependencies: [],
            path: "Sources/TermQCore"
        ),
        // Shared models and utilities for CLI and MCP (no SwiftUI dependencies)
        .target(
            name: "TermQShared",
            dependencies: [],
            path: "Sources/TermQShared"
        ),
        // Main app
        .executableTarget(
            name: "TermQ",
            dependencies: [
                "TermQCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/TermQ",
            resources: [
                .copy("Resources/Help"),
                // Process all localization folders
                .process("Resources/ar.lproj"),
                .process("Resources/ca.lproj"),
                .process("Resources/cs.lproj"),
                .process("Resources/da.lproj"),
                .process("Resources/de.lproj"),
                .process("Resources/el.lproj"),
                .process("Resources/en-AU.lproj"),
                .process("Resources/en-GB.lproj"),
                .process("Resources/en.lproj"),
                .process("Resources/es-419.lproj"),
                .process("Resources/es.lproj"),
                .process("Resources/fi.lproj"),
                .process("Resources/fr-CA.lproj"),
                .process("Resources/fr.lproj"),
                .process("Resources/he.lproj"),
                .process("Resources/hi.lproj"),
                .process("Resources/hr.lproj"),
                .process("Resources/hu.lproj"),
                .process("Resources/id.lproj"),
                .process("Resources/it.lproj"),
                .process("Resources/ja.lproj"),
                .process("Resources/ko.lproj"),
                .process("Resources/ms.lproj"),
                .process("Resources/nl.lproj"),
                .process("Resources/no.lproj"),
                .process("Resources/pl.lproj"),
                .process("Resources/pt-PT.lproj"),
                .process("Resources/pt.lproj"),
                .process("Resources/ro.lproj"),
                .process("Resources/ru.lproj"),
                .process("Resources/sk.lproj"),
                .process("Resources/sl.lproj"),
                .process("Resources/sv.lproj"),
                .process("Resources/th.lproj"),
                .process("Resources/tr.lproj"),
                .process("Resources/uk.lproj"),
                .process("Resources/vi.lproj"),
                .process("Resources/zh-Hans.lproj"),
                .process("Resources/zh-Hant.lproj"),
                .process("Resources/zh-HK.lproj")
            ]
        ),
        // CLI tool
        .executableTarget(
            name: "termq-cli",
            dependencies: [
                "TermQShared",
                "MCPServerLib",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/termq-cli"
        ),
        // MCP Server library (shared logic)
        .target(
            name: "MCPServerLib",
            dependencies: [
                "TermQShared",
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
            dependencies: ["MCPServerLib", "TermQShared"],
            path: "Tests/MCPServerLibTests"
        ),
        .testTarget(
            name: "TermQSharedTests",
            dependencies: ["TermQShared"],
            path: "Tests/TermQSharedTests"
        )
    ]
)
