import CryptoKit
import Foundation
import XCTest

@testable import TermQ

/// Exercises `SecureStorage` against an injected in-memory key store and a
/// temp config directory. No keychain access; no real Application Support
/// directory writes.
final class SecureStorageTests: XCTestCase {

    private var configDir: URL!
    private var keyStore: InMemoryEncryptionKeyStore!

    override func setUpWithError() throws {
        configDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SecureStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        keyStore = InMemoryEncryptionKeyStore()
    }

    override func tearDownWithError() throws {
        if let configDir {
            try? FileManager.default.removeItem(at: configDir)
        }
    }

    private func makeStorage() -> SecureStorage {
        SecureStorage(keyStore: keyStore, configDirectory: configDir)
    }

    // MARK: - Round-trip

    func test_storeAndRetrieve_returnsValue() async throws {
        let storage = makeStorage()
        try await storage.storeSecret(id: "k1", value: "secret-value")

        let value = try await storage.retrieveSecret(id: "k1")
        XCTAssertEqual(value, "secret-value")
    }

    func test_retrieve_unknownId_returnsNil() async throws {
        let storage = makeStorage()
        let value = try await storage.retrieveSecret(id: "missing")
        XCTAssertNil(value)
    }

    func test_storeOverwrites_previousValue() async throws {
        let storage = makeStorage()
        try await storage.storeSecret(id: "k", value: "first")
        try await storage.storeSecret(id: "k", value: "second")

        let value = try await storage.retrieveSecret(id: "k")
        XCTAssertEqual(value, "second")
    }

    func test_delete_removesValue() async throws {
        let storage = makeStorage()
        try await storage.storeSecret(id: "k", value: "v")
        try await storage.deleteSecret(id: "k")

        let value = try await storage.retrieveSecret(id: "k")
        XCTAssertNil(value)
    }

    func test_listSecretIds_returnsAllStoredKeys() async throws {
        let storage = makeStorage()
        try await storage.storeSecret(id: "a", value: "1")
        try await storage.storeSecret(id: "b", value: "2")
        try await storage.storeSecret(id: "c", value: "3")

        let ids = try await storage.listSecretIds()
        XCTAssertEqual(Set(ids), ["a", "b", "c"])
    }

    // MARK: - Persistence to disk

    func test_storeWritesEncryptedFileToConfigDirectory() async throws {
        let storage = makeStorage()
        try await storage.storeSecret(id: "k", value: "v")

        let secretsURL = configDir.appendingPathComponent("secrets.enc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: secretsURL.path))

        // File contents must NOT contain the plaintext.
        let raw = try Data(contentsOf: secretsURL)
        let asString = String(data: raw, encoding: .utf8) ?? ""
        XCTAssertFalse(asString.contains("v"), "Secret should be encrypted on disk")
    }

    func test_freshStorage_sameKeyStore_sameConfigDir_readsPriorWrites() async throws {
        let first = makeStorage()
        try await first.storeSecret(id: "k", value: "v")

        // New SecureStorage instance over the same backing store + dir
        let second = makeStorage()
        let value = try await second.retrieveSecret(id: "k")
        XCTAssertEqual(value, "v")
    }

    // MARK: - hasEncryptionKey

    func test_hasEncryptionKey_falseWithEmptyKeyStore() async {
        let storage = makeStorage()
        let has = await storage.hasEncryptionKey()
        XCTAssertFalse(has)
    }

    func test_hasEncryptionKey_trueAfterFirstWrite() async throws {
        let storage = makeStorage()
        try await storage.storeSecret(id: "k", value: "v")

        let has = await storage.hasEncryptionKey()
        XCTAssertTrue(has)
    }

    // MARK: - resetEncryptionKey

    func test_resetEncryptionKey_removesSecretsFileAndKey() async throws {
        let storage = makeStorage()
        try await storage.storeSecret(id: "k", value: "v")

        try await storage.resetEncryptionKey()

        let secretsURL = configDir.appendingPathComponent("secrets.enc")
        XCTAssertFalse(FileManager.default.fileExists(atPath: secretsURL.path))
        let has = await storage.hasEncryptionKey()
        XCTAssertFalse(has)
    }

    // MARK: - export / import

    func test_exportThenImport_roundTrip_preservesSecrets() async throws {
        let source = makeStorage()
        try await source.storeSecret(id: "k1", value: "v1")
        try await source.storeSecret(id: "k2", value: "v2")
        let blob = try await source.exportSecrets()
        XCTAssertFalse(blob.isEmpty)

        // Fresh storage backed by the SAME key store (so decryption succeeds)
        // but a fresh config dir to prove import writes the file.
        let freshDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SecureStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: freshDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: freshDir) }

        let dest = SecureStorage(keyStore: keyStore, configDirectory: freshDir)
        try await dest.importSecrets(blob)

        let v1 = try await dest.retrieveSecret(id: "k1")
        let v2 = try await dest.retrieveSecret(id: "k2")
        XCTAssertEqual(v1, "v1")
        XCTAssertEqual(v2, "v2")
    }

    func test_exportEmpty_returnsEmptyData() async throws {
        let storage = makeStorage()
        let blob = try await storage.exportSecrets()
        XCTAssertTrue(blob.isEmpty)
    }

    func test_importEmpty_isNoOp() async throws {
        let storage = makeStorage()
        try await storage.importSecrets(Data())
        let secretsURL = configDir.appendingPathComponent("secrets.enc")
        XCTAssertFalse(FileManager.default.fileExists(atPath: secretsURL.path))
    }

    // MARK: - clearCache

    func test_clearCache_forcesReloadFromDisk() async throws {
        let storage = makeStorage()
        try await storage.storeSecret(id: "k", value: "v")

        // Mutate disk directly behind the actor to prove the cache is what we
        // were reading. After clearCache, retrieveSecret must re-read.
        let secretsURL = configDir.appendingPathComponent("secrets.enc")
        try FileManager.default.removeItem(at: secretsURL)

        await storage.clearCache()
        let value = try await storage.retrieveSecret(id: "k")
        XCTAssertNil(value)
    }
}

// MARK: - InMemoryEncryptionKeyStore

final class InMemoryEncryptionKeyStoreTests: XCTestCase {

    func test_load_emptyStore_throwsItemNotFound() {
        let store = InMemoryEncryptionKeyStore()
        XCTAssertThrowsError(try store.load()) { error in
            guard let err = error as? SecureStorageError,
                case .keychainError(let status) = err
            else {
                XCTFail("Expected keychainError, got \(error)")
                return
            }
            XCTAssertEqual(status, errSecItemNotFound)
        }
    }

    func test_storeThenLoad_returnsSameKey() throws {
        let store = InMemoryEncryptionKeyStore()
        let key = SymmetricKey(size: .bits256)
        try store.store(key)
        let loaded = try store.load()

        let original = key.withUnsafeBytes { Data($0) }
        let restored = loaded.withUnsafeBytes { Data($0) }
        XCTAssertEqual(original, restored)
    }

    func test_delete_clearsStoredKey() throws {
        let store = InMemoryEncryptionKeyStore(initial: SymmetricKey(size: .bits256))
        XCTAssertNoThrow(try store.load())
        try store.delete()
        XCTAssertThrowsError(try store.load())
    }

    func test_initial_returnsKeyOnFirstLoad() throws {
        let key = SymmetricKey(size: .bits256)
        let store = InMemoryEncryptionKeyStore(initial: key)
        let loaded = try store.load()

        let original = key.withUnsafeBytes { Data($0) }
        let restored = loaded.withUnsafeBytes { Data($0) }
        XCTAssertEqual(original, restored)
    }
}
