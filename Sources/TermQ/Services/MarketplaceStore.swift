import Foundation

/// Persisted list of user-added marketplaces.
///
/// Stored at ~/Library/Application Support/TermQ/marketplaces.json.
/// Never writes to YNH's directories.
@MainActor
final class MarketplaceStore: ObservableObject {
    static let shared = MarketplaceStore()

    @Published private(set) var marketplaces: [Marketplace] = []

    /// Most recent persistence error, if any. Surfaces silent disk failures
    /// (write permission, disk full, encoding) to the UI.
    @Published private(set) var lastPersistenceError: String?

    /// If non-nil, this marketplace is pre-selected in the browser (e.g. after wizard handoff).
    @Published var preselectedMarketplaceID: UUID?
    /// If non-nil, the HarnessIncludePicker should open pre-targeted at this harness.
    @Published var preselectedHarnessTarget: String?

    private let fileURL: URL
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private static let defaultsSeedKey = "marketplaces.defaultsSeeded.v1"
    private static let removedDefaultsKey = "marketplaces.removedDefaultURLs.v1"

    /// Designated initialiser. Defaults to the production location and standard UserDefaults;
    /// tests inject a temp file and an isolated UserDefaults suite.
    init(fileURL: URL? = nil, defaults: UserDefaults = .standard) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            guard
                let appSupport = FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first
            else { fatalError("applicationSupportDirectory unavailable") }
            let dir = appSupport.appendingPathComponent("TermQ", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("marketplaces.json")
        }
        self.defaults = defaults

        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        load()
        seedDefaultsIfNeeded()
    }

    private func seedDefaultsIfNeeded() {
        guard !defaults.bool(forKey: Self.defaultsSeedKey) else { return }
        // Respect tombstones on re-seed (e.g. after a defaults reset). Only the
        // explicit "Restore Defaults" button bypasses tombstones via force: true.
        restoreDefaults(force: false)
        defaults.set(true, forKey: Self.defaultsSeedKey)
    }

    /// Add any default marketplaces that are not already present.
    ///
    /// - Parameter force: When `true`, ignores tombstones (URLs the user has explicitly removed)
    ///                    and clears them. Use this for the explicit "Restore Defaults" button.
    ///                    When `false` (default), tombstoned defaults stay removed.
    func restoreDefaults(force: Bool = false) {
        if force {
            defaults.removeObject(forKey: Self.removedDefaultsKey)
        }
        let tombstones = removedDefaultURLs
        for seed in KnownMarketplaces.all {
            if !force, tombstones.contains(seed.url) { continue }
            add(
                Marketplace(
                    id: UUID(), name: seed.name, owner: seed.owner,
                    description: seed.description, vendor: seed.vendor,
                    url: seed.url, ref: nil, plugins: [], lastFetched: nil, fetchError: nil
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
        do {
            let data = try encoder.encode(marketplaces)
            try data.write(to: fileURL, options: .atomic)
            lastPersistenceError = nil
        } catch {
            let message = "Failed to persist marketplaces: \(error.localizedDescription)"
            lastPersistenceError = message
            TermQLogger.io.error(message)
        }
    }

    // MARK: - Tombstones

    private var removedDefaultURLs: Set<String> {
        Set(defaults.stringArray(forKey: Self.removedDefaultsKey) ?? [])
    }

    private func tombstone(url: String) {
        var current = removedDefaultURLs
        current.insert(url)
        defaults.set(Array(current), forKey: Self.removedDefaultsKey)
    }

    private func untombstone(url: String) {
        var current = removedDefaultURLs
        current.remove(url)
        defaults.set(Array(current), forKey: Self.removedDefaultsKey)
    }

    // MARK: - Mutations

    func add(_ marketplace: Marketplace) {
        guard !marketplaces.contains(where: { $0.url == marketplace.url && $0.vendor == marketplace.vendor }) else {
            return
        }
        // Adding a known-default URL clears its tombstone so future seed checks treat it as present.
        if KnownMarketplaces.all.contains(where: { $0.url == marketplace.url }) {
            untombstone(url: marketplace.url)
        }
        marketplaces.append(marketplace)
        save()
    }

    func remove(id: UUID) {
        guard let removed = marketplaces.first(where: { $0.id == id }) else { return }
        marketplaces.removeAll { $0.id == id }
        // If this URL is in the seed list, tombstone it so we don't re-add it on the next launch
        // (defence against any future seed re-run, e.g. after a defaults reset or version bump).
        if KnownMarketplaces.all.contains(where: { $0.url == removed.url }) {
            tombstone(url: removed.url)
        }
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
