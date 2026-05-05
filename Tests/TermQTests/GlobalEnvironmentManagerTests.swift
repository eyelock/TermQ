import Foundation
import TermQCore
import XCTest

@testable import TermQ

/// Exercises `GlobalEnvironmentManager` against an injected `SecureStorage`
/// (in-memory key store + temp dir) and an isolated `UserDefaults` suite —
/// no Keychain access, no real Application Support writes.
@MainActor
final class GlobalEnvironmentManagerTests: XCTestCase {

    private var configDir: URL!
    private var keyStore: InMemoryEncryptionKeyStore!
    private var secureStorage: SecureStorage!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        configDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GEMTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        keyStore = InMemoryEncryptionKeyStore()
        secureStorage = SecureStorage(keyStore: keyStore, configDirectory: configDir)
        suiteName = "GEMTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        if let configDir { try? FileManager.default.removeItem(at: configDir) }
        defaults?.removePersistentDomain(forName: suiteName)
    }

    private func makeManager(autoLoad: Bool = false) -> GlobalEnvironmentManager {
        GlobalEnvironmentManager(
            secureStorage: secureStorage,
            userDefaults: defaults,
            autoLoad: autoLoad
        )
    }

    // MARK: - Initial state

    func test_initialState_emptyVariables() {
        let mgr = makeManager()
        XCTAssertTrue(mgr.variables.isEmpty)
        XCTAssertFalse(mgr.isLoading)
        XCTAssertNil(mgr.error)
    }

    // MARK: - Add

    func test_addVariable_nonSecret_appendsAndPersists() async throws {
        let mgr = makeManager()
        let v = EnvironmentVariable(key: "FOO", value: "bar", isSecret: false)
        try await mgr.addVariable(v)

        XCTAssertEqual(mgr.variables.count, 1)
        XCTAssertEqual(mgr.variables[0].key, "FOO")

        // Persisted to UserDefaults
        XCTAssertNotNil(defaults.data(forKey: "GlobalEnvironmentVariables"))
    }

    func test_addVariable_secret_storesInSecureStorage() async throws {
        let mgr = makeManager()
        let v = EnvironmentVariable(key: "API_KEY", value: "topsecret", isSecret: true)
        try await mgr.addVariable(v)

        XCTAssertEqual(mgr.variables.count, 1)
        let stored = try await secureStorage.retrieveSecret(id: "global-\(v.id.uuidString)")
        XCTAssertEqual(stored, "topsecret")
    }

    func test_addVariable_duplicateKey_throws() async throws {
        let mgr = makeManager()
        try await mgr.addVariable(EnvironmentVariable(key: "FOO", value: "1", isSecret: false))

        do {
            try await mgr.addVariable(EnvironmentVariable(key: "FOO", value: "2", isSecret: false))
            XCTFail("Expected duplicateKey error")
        } catch let error as GlobalEnvironmentError {
            guard case .duplicateKey = error else {
                XCTFail("Expected duplicateKey, got \(error)")
                return
            }
        }
    }

    func test_addVariable_duplicateKey_isCaseInsensitive() async throws {
        let mgr = makeManager()
        try await mgr.addVariable(EnvironmentVariable(key: "foo", value: "1", isSecret: false))

        do {
            try await mgr.addVariable(EnvironmentVariable(key: "FOO", value: "2", isSecret: false))
            XCTFail("Expected duplicateKey error")
        } catch is GlobalEnvironmentError {
            // expected
        }
    }

    func test_addVariable_invalidKey_throws() async throws {
        let mgr = makeManager()
        do {
            // Leading digit — invalid env var name.
            try await mgr.addVariable(EnvironmentVariable(key: "1BAD", value: "v", isSecret: false))
            XCTFail("Expected invalidKey error")
        } catch let error as GlobalEnvironmentError {
            guard case .invalidKey = error else {
                XCTFail("Expected invalidKey, got \(error)")
                return
            }
        }
    }

    // MARK: - Update

    func test_updateVariable_changesValue() async throws {
        let mgr = makeManager()
        var v = EnvironmentVariable(key: "FOO", value: "1", isSecret: false)
        try await mgr.addVariable(v)

        v.value = "2"
        try await mgr.updateVariable(v)

        XCTAssertEqual(mgr.variables[0].value, "2")
    }

    func test_updateVariable_secretToNonSecret_removesFromSecureStorage() async throws {
        let mgr = makeManager()
        var v = EnvironmentVariable(key: "FOO", value: "secret", isSecret: true)
        try await mgr.addVariable(v)

        v.isSecret = false
        v.value = "plain"
        try await mgr.updateVariable(v)

        let stored = try await secureStorage.retrieveSecret(id: "global-\(v.id.uuidString)")
        XCTAssertNil(stored)
    }

    func test_updateVariable_nonSecretToSecret_storesInSecureStorage() async throws {
        let mgr = makeManager()
        var v = EnvironmentVariable(key: "FOO", value: "plain", isSecret: false)
        try await mgr.addVariable(v)

        v.isSecret = true
        v.value = "secret"
        try await mgr.updateVariable(v)

        let stored = try await secureStorage.retrieveSecret(id: "global-\(v.id.uuidString)")
        XCTAssertEqual(stored, "secret")
    }

    func test_updateVariable_unknownId_throwsNotFound() async throws {
        let mgr = makeManager()
        let v = EnvironmentVariable(key: "FOO", value: "1", isSecret: false)
        do {
            try await mgr.updateVariable(v)
            XCTFail("Expected variableNotFound")
        } catch let error as GlobalEnvironmentError {
            guard case .variableNotFound = error else {
                XCTFail("Expected variableNotFound, got \(error)")
                return
            }
        }
    }

    // MARK: - Delete

    func test_deleteVariable_removesFromArray() async throws {
        let mgr = makeManager()
        let v = EnvironmentVariable(key: "FOO", value: "1", isSecret: false)
        try await mgr.addVariable(v)

        try await mgr.deleteVariable(id: v.id)

        XCTAssertTrue(mgr.variables.isEmpty)
    }

    func test_deleteVariable_secret_alsoRemovesFromSecureStorage() async throws {
        let mgr = makeManager()
        let v = EnvironmentVariable(key: "API_KEY", value: "secret", isSecret: true)
        try await mgr.addVariable(v)

        try await mgr.deleteVariable(id: v.id)

        let stored = try await secureStorage.retrieveSecret(id: "global-\(v.id.uuidString)")
        XCTAssertNil(stored)
    }

    func test_deleteAllSecrets_keepsNonSecrets() async throws {
        let mgr = makeManager()
        try await mgr.addVariable(EnvironmentVariable(key: "PLAIN", value: "v", isSecret: false))
        try await mgr.addVariable(EnvironmentVariable(key: "API_KEY", value: "s", isSecret: true))

        await mgr.deleteAllSecrets()

        XCTAssertEqual(mgr.variables.count, 1)
        XCTAssertEqual(mgr.variables[0].key, "PLAIN")
    }

    // MARK: - load (round-trip across instances)

    func test_load_restoresPersistedVariables() async throws {
        let first = makeManager()
        try await first.addVariable(EnvironmentVariable(key: "PLAIN", value: "p", isSecret: false))
        try await first.addVariable(EnvironmentVariable(key: "API_KEY", value: "s", isSecret: true))

        let second = makeManager()
        await second.load()

        XCTAssertEqual(second.variables.count, 2)
        let keys = Set(second.variables.map(\.key))
        XCTAssertEqual(keys, ["PLAIN", "API_KEY"])
        // Secret value is rehydrated from SecureStorage
        let apiKey = second.variables.first { $0.key == "API_KEY" }
        XCTAssertEqual(apiKey?.value, "s")
    }

    // MARK: - resolvedVariables

    func test_resolvedVariables_returnsAllKeyValuePairs() async throws {
        let mgr = makeManager()
        try await mgr.addVariable(EnvironmentVariable(key: "PLAIN", value: "p", isSecret: false))
        try await mgr.addVariable(EnvironmentVariable(key: "API_KEY", value: "s", isSecret: true))

        let resolved = try await mgr.resolvedVariables()
        XCTAssertEqual(resolved["PLAIN"], "p")
        XCTAssertEqual(resolved["API_KEY"], "s")
    }

    // MARK: - keyExists

    func test_keyExists_caseInsensitive() async throws {
        let mgr = makeManager()
        try await mgr.addVariable(EnvironmentVariable(key: "foo", value: "v", isSecret: false))
        XCTAssertTrue(mgr.keyExists("FOO"))
        XCTAssertTrue(mgr.keyExists("foo"))
        XCTAssertFalse(mgr.keyExists("BAR"))
    }

    func test_keyExists_excludingId_returnsFalseForSelf() async throws {
        let mgr = makeManager()
        let v = EnvironmentVariable(key: "FOO", value: "v", isSecret: false)
        try await mgr.addVariable(v)
        XCTAssertFalse(mgr.keyExists("FOO", excludingId: v.id))
    }
}
