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
        // Pinned post-v1.13.0: includes cursor ghosting (DECTCEM), EV_VANISHED crash,
        // PTY resize/Auto Layout, and SGR mouse encoding fixes. Fork eyelock/SwiftTerm archived.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", revision: "b6ce28a4b222b06d76a3fd44e904e00a95044d53"),
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
