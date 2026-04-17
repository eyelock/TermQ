import Foundation

struct KnownMarketplace: Sendable {
    let name: String
    let owner: String
    let description: String
    let vendor: MarketplaceVendor
    let url: String
}

enum KnownMarketplaces {
    static let all: [KnownMarketplace] = [
        KnownMarketplace(
            name: "Claude Plugins Official",
            owner: "Anthropic",
            description: "The official catalog of Claude Code plugins from Anthropic.",
            vendor: .claude,
            url: "https://github.com/anthropics/claude-plugins-official"
        )
        // Cursor deliberately omitted from v1: no fetchable Git index available.
    ]
}
