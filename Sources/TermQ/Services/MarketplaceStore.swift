import Foundation

/// Persisted list of user-added marketplaces.
///
/// Stored at ~/Library/Application Support/TermQ/marketplaces.json.
/// Never writes to YNH's directories.
@MainActor
final class MarketplaceStore: ObservableObject {
    static let shared = MarketplaceStore()

    @Published private(set) var marketplaces: [Marketplace] = []

    /// If non-nil, this marketplace is pre-selected in the browser (e.g. after wizard handoff).
    @Published var preselectedMarketplaceID: UUID?
    /// If non-nil, the HarnessIncludePicker should open pre-targeted at this harness.
    @Published var preselectedHarnessTarget: String?

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        guard
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else { fatalError("applicationSupportDirectory unavailable") }
        let dir = appSupport.appendingPathComponent("TermQ", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("marketplaces.json")

        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        load()
        seedDefaultsIfNeeded()
    }

    private static let defaultsSeedKey = "marketplaces.defaultsSeeded.v1"

    private func seedDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.defaultsSeedKey) else { return }
        restoreDefaults()
        UserDefaults.standard.set(true, forKey: Self.defaultsSeedKey)
    }

    /// Add any default marketplaces that are not already present.
    func restoreDefaults() {
        for seed in KnownMarketplaces.all {
            add(
                Marketplace(
                    id: UUID(), name: seed.name, owner: seed.owner,
                    description: seed.description, vendor: seed.vendor,
                    url: seed.url, plugins: [], lastFetched: nil, fetchError: nil
                )
            )
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        marketplaces = (try? decoder.decode([Marketplace].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? encoder.encode(marketplaces) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Mutations

    func add(_ marketplace: Marketplace) {
        guard !marketplaces.contains(where: { $0.url == marketplace.url && $0.vendor == marketplace.vendor }) else {
            return
        }
        marketplaces.append(marketplace)
        save()
    }

    func remove(id: UUID) {
        marketplaces.removeAll { $0.id == id }
        save()
    }

    func update(_ marketplace: Marketplace) {
        guard let idx = marketplaces.firstIndex(where: { $0.id == marketplace.id }) else { return }
        marketplaces[idx] = marketplace
        save()
    }

    /// Mark a fetch as in-progress (clears prior error).
    func markFetching(id: UUID) {
        guard let idx = marketplaces.firstIndex(where: { $0.id == id }) else { return }
        marketplaces[idx].fetchError = nil
        save()
    }

    func stale(daysThreshold: Int = 7) -> [Marketplace] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -daysThreshold, to: Date()) ?? Date()
        return marketplaces.filter { marketplace in
            guard let last = marketplace.lastFetched else { return true }
            return last < cutoff
        }
    }
}
