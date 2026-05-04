import XCTest

@testable import TermQ

@MainActor
final class MarketplaceStoreTests: XCTestCase {

    private var tempDir: URL!
    private var fileURL: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MarketplaceStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fileURL = tempDir.appendingPathComponent("marketplaces.json")
        suiteName = "MarketplaceStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Seeding

    func test_firstLaunch_seedsKnownMarketplaces() {
        let store = MarketplaceStore(fileURL: fileURL, defaults: defaults)
        let urls = Set(store.marketplaces.map(\.url))
        for seed in KnownMarketplaces.all {
            XCTAssertTrue(urls.contains(seed.url), "Seed missing: \(seed.url)")
        }
    }

    func test_secondLaunch_doesNotReseed() {
        _ = MarketplaceStore(fileURL: fileURL, defaults: defaults)
        let store2 = MarketplaceStore(fileURL: fileURL, defaults: defaults)
        // Should match KnownMarketplaces count exactly — no duplicates from a re-seed
        XCTAssertEqual(store2.marketplaces.count, KnownMarketplaces.all.count)
    }

    // MARK: - Persistence round-trip

    func test_remove_persistsAcrossRelaunch() {
        let store = MarketplaceStore(fileURL: fileURL, defaults: defaults)
        let target = store.marketplaces.first { $0.url == "https://github.com/eyelock/assistants" }
        let id = try! XCTUnwrap(target?.id)
        store.remove(id: id)
        XCTAssertFalse(store.marketplaces.contains(where: { $0.id == id }))

        // Simulate relaunch
        let reborn = MarketplaceStore(fileURL: fileURL, defaults: defaults)
        XCTAssertFalse(
            reborn.marketplaces.contains(where: { $0.url == "https://github.com/eyelock/assistants" }),
            "Removed default marketplace should not reappear after relaunch"
        )
    }

    func test_add_persistsAcrossRelaunch() {
        let store = MarketplaceStore(fileURL: fileURL, defaults: defaults)
        let userAdded = Marketplace(
            id: UUID(), name: "Custom", owner: "user", description: nil,
            vendor: .claude, url: "https://example.com/custom", ref: nil,
            plugins: [], lastFetched: nil, fetchError: nil
        )
        store.add(userAdded)

        let reborn = MarketplaceStore(fileURL: fileURL, defaults: defaults)
        XCTAssertTrue(reborn.marketplaces.contains(where: { $0.url == "https://example.com/custom" }))
    }

    // MARK: - Tombstones (defence-in-depth against re-seed)

    func test_removedDefault_staysRemoved_evenIfSeedFlagCleared() {
        let store = MarketplaceStore(fileURL: fileURL, defaults: defaults)
        let target = store.marketplaces.first { $0.url == "https://github.com/eyelock/assistants" }
        store.remove(id: try! XCTUnwrap(target?.id))

        // Simulate "the seed key got cleared somehow" (defaults wipe, version bump, etc.)
        defaults.removeObject(forKey: "marketplaces.defaultsSeeded.v1")

        let reborn = MarketplaceStore(fileURL: fileURL, defaults: defaults)
        XCTAssertFalse(
            reborn.marketplaces.contains(where: { $0.url == "https://github.com/eyelock/assistants" }),
            "Tombstone should prevent a re-seed from re-adding a removed default"
        )
    }

    func test_restoreDefaults_force_clearsTombstones() {
        let store = MarketplaceStore(fileURL: fileURL, defaults: defaults)
        let target = store.marketplaces.first { $0.url == "https://github.com/eyelock/assistants" }
        store.remove(id: try! XCTUnwrap(target?.id))

        store.restoreDefaults(force: true)
        XCTAssertTrue(
            store.marketplaces.contains(where: { $0.url == "https://github.com/eyelock/assistants" }),
            "Force-restoring defaults should override tombstones"
        )

        // And the tombstone should be cleared, so a relaunch keeps the entry.
        let reborn = MarketplaceStore(fileURL: fileURL, defaults: defaults)
        XCTAssertTrue(reborn.marketplaces.contains(where: { $0.url == "https://github.com/eyelock/assistants" }))
    }

    func test_addingBackARemovedDefault_clearsItsTombstone() {
        let store = MarketplaceStore(fileURL: fileURL, defaults: defaults)
        let target = store.marketplaces.first { $0.url == "https://github.com/eyelock/assistants" }
        store.remove(id: try! XCTUnwrap(target?.id))

        // User re-adds the same URL by hand via the Add sheet.
        store.add(
            Marketplace(
                id: UUID(), name: "eyelock assistants", owner: "eyelock", description: nil,
                vendor: .claude, url: "https://github.com/eyelock/assistants", ref: nil,
                plugins: [], lastFetched: nil, fetchError: nil
            )
        )

        // Simulate re-seed conditions; entry should remain (tombstone cleared by add).
        defaults.removeObject(forKey: "marketplaces.defaultsSeeded.v1")
        let reborn = MarketplaceStore(fileURL: fileURL, defaults: defaults)
        let count = reborn.marketplaces.filter { $0.url == "https://github.com/eyelock/assistants" }.count
        XCTAssertEqual(count, 1, "Re-added default should appear exactly once after a re-seed")
    }

    // MARK: - Add dedup

    func test_add_deduplicatesByURLAndVendor() {
        let store = MarketplaceStore(fileURL: fileURL, defaults: defaults)
        let before = store.marketplaces.count
        store.add(
            Marketplace(
                id: UUID(), name: "dup", owner: "x", description: nil,
                vendor: .claude, url: "https://github.com/eyelock/assistants", ref: nil,
                plugins: [], lastFetched: nil, fetchError: nil
            )
        )
        XCTAssertEqual(store.marketplaces.count, before, "Duplicate URL+vendor should not be added")
    }
}
