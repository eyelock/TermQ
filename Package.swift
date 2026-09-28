// swift-tools-version:6.0
import PackageDescription

// Strict-concurrency=complete is applied to every target as an explicit
// guard rail. Swift 6 language mode (the default for swift-tools 6.0)
// enables it implicitly, but stating it here documents intent and ensures
// the project still gates concurrency violations if a future migration
// loosens the language mode for any target. Adopted in
// `refactor/loadstate-and-identity` to lock in the discipline that
// prevented the 0.9.3 actor-isolation crash class.
let strictConcurrencySettings: [SwiftSetting] = [
    .unsafeFlags(["-strict-concurrency=complete"])
]

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
        // v1.20.0 (2026-08-18) is the last release on the 1.x API; upstream main is now
        // 2.x (no getTerminal(), new IO pipeline) and needs a separate migration.
        // Adds since the 2026-08-03 pin: Kitty keyboard text loss with alternate-key
        // reporting (#624), stale rows when repainting in place while scrolled back
        // (#620), Alternate Scroll Mode 1007 tracked and honoured by the wheel, full
        // reset notifying the view, cursor refresh on focus change, link-open during
        // drag regression, combining glyphs after cursor movement, dropped child-exit
        // for fast-exiting processes (#617), OSC 8 print-time attribution (#635).
        // 2.x: pinned to upstream main 2026-09-27 (no 2.0.0 tag yet). See the 2.x
        // migration notes in the PR for what changed at the integration seam.
        .package(
            url: "https://github.com/migueldeicaza/SwiftTerm.git",
            revision: "fe4fb45d5888ce33ff3788d6873870a73894a41b"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        // MCP Swift SDK for Model Context Protocol support
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.0"),
        // Sparkle for auto-updates
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        // Core library with models (testable)
        .target(
            name: "TermQCore",
            dependencies: [],
            path: "Sources/TermQCore",
            swiftSettings: strictConcurrencySettings
        ),
        // Shared models and utilities for CLI and MCP (no SwiftUI dependencies)
        .target(
            name: "TermQShared",
            dependencies: [],
            path: "Sources/TermQShared",
            swiftSettings: strictConcurrencySettings
        ),
        // Main app
        .executableTarget(
            name: "TermQ",
            dependencies: [
                "TermQCore",
                "TermQShared",
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
            ],
            swiftSettings: strictConcurrencySettings
        ),
        // CLI command library (testable — logic separated from executable entry point)
        .target(
            name: "TermQCLICore",
            dependencies: [
                "TermQShared",
                "MCPServerLib",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/TermQCLICore",
            swiftSettings: strictConcurrencySettings
        ),
        // CLI tool entry point (thin wrapper over TermQCLICore)
        .executableTarget(
            name: "termq-cli",
            dependencies: ["TermQCLICore"],
            path: "Sources/termq-cli",
            swiftSettings: strictConcurrencySettings
        ),
        // MCP Server library (shared logic)
        .target(
            name: "MCPServerLib",
            dependencies: [
                "TermQShared",
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources/MCPServerLib",
            swiftSettings: strictConcurrencySettings
        ),
        // MCP Server CLI binary
        .executableTarget(
            name: "termqmcp",
            dependencies: [
                "MCPServerLib",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/MCPServer-CLI",
            swiftSettings: strictConcurrencySettings
        ),
        // Tests
        .testTarget(
            name: "TermQTests",
            dependencies: [
                "TermQ",
                "TermQCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Tests/TermQTests",
            swiftSettings: strictConcurrencySettings
        ),
        .testTarget(
            name: "MCPServerLibTests",
            dependencies: ["MCPServerLib", "TermQShared"],
            path: "Tests/MCPServerLibTests",
            swiftSettings: strictConcurrencySettings
        ),
        .testTarget(
            name: "TermQSharedTests",
            dependencies: ["TermQShared"],
            path: "Tests/TermQSharedTests",
            swiftSettings: strictConcurrencySettings
        ),
        .testTarget(
            name: "TermQCLITests",
            dependencies: ["TermQCLICore", "TermQShared", "MCPServerLib"],
            path: "Tests/TermQCLITests",
            swiftSettings: strictConcurrencySettings
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["MCPServerLib", "TermQCLICore", "TermQShared"],
            path: "Tests/IntegrationTests",
            swiftSettings: strictConcurrencySettings
        )
    ]
)
