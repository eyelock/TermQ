import CryptoKit
import Foundation
import Security

/// Backing store for the symmetric key used by `SecureStorage` to AES-GCM-encrypt
/// the secrets file. The protocol exists so tests can inject an in-memory
/// implementation instead of touching the real Keychain (or the debug-build
/// file-based key on disk).
public protocol EncryptionKeyStore: Sendable {
    /// Returns the stored key, or throws `SecureStorageError.keychainError(errSecItemNotFound)`
    /// when no key has been written yet.
    func load() throws -> SymmetricKey
    /// Persists the given key, overwriting any existing entry.
    func store(_ key: SymmetricKey) throws
    /// Removes the stored key. Idempotent — succeeds when the key is already absent.
    func delete() throws
}

/// Live key store with a hybrid storage strategy:
///
/// - **Debug build (`TERMQ_DEBUG_BUILD`)**: file-based only. The ad-hoc-signed debug binary
///   gets a fresh code-signing hash on every build, so the Keychain would prompt on every
///   launch. The file is 0o600 and lives in the app's data directory.
///
/// - **Release build**: Data Protection Keychain when authorized (i.e. the app carries a
///   `keychain-access-groups` entitlement validated by an embedded provisioning profile);
///   file-based fallback when not. The Data Protection Keychain is what Apple recommends
///   (see TN3137 "On Mac keychain APIs and implementations"), but using it requires
///   provisioning-profile authorization that the local ad-hoc `make release-app` flow can't
///   produce. The fallback keeps secrets working everywhere; once CI is wired up to embed
///   a provisioning profile, the same code automatically switches to the Keychain with no
///   further changes.
///
/// On first load the release path also consults the legacy file-based Login Keychain so
/// installations that pre-date the Data Protection Keychain migration (commit 920cb46) can
/// recover their key. The key is migrated into the current storage and the legacy entry
/// is deleted on success.
public struct LiveEncryptionKeyStore: EncryptionKeyStore {
    public let service: String
    public let account: String
    public let keyDirectory: URL

    public init(service: String, account: String, debugKeyDirectory: URL) {
        self.service = service
        self.account = account
        self.keyDirectory = debugKeyDirectory
    }

    private var fileKeyURL: URL {
        keyDirectory.appendingPathComponent(".enc-key")
    }

    #if TERMQ_DEBUG_BUILD

        public func load() throws -> SymmetricKey {
            try loadFromFile()
        }

        public func store(_ key: SymmetricKey) throws {
            try storeInFile(key)
        }

        public func delete() throws {
            try? FileManager.default.removeItem(at: fileKeyURL)
        }

    #else

        public func load() throws -> SymmetricKey {
            if let key = try? loadFromDataProtectionKeychain() {
                return key
            }
            if let key = try? loadFromFile() {
                return key
            }
            // Migration: recover keys stored by pre-920cb46 builds in the Login Keychain.
            if let key = try? loadFromLoginKeychain() {
                try? store(key)
                try? deleteFromLoginKeychain()
                return key
            }
            throw SecureStorageError.keychainError(errSecItemNotFound)
        }

        public func store(_ key: SymmetricKey) throws {
            let keyData = key.withUnsafeBytes { Data($0) }

            try? deleteFromDataProtectionKeychain()
            let dpQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: keyData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
                kSecUseDataProtectionKeychain as String: true,
            ]
            let dpStatus = SecItemAdd(dpQuery as CFDictionary, nil)
            if dpStatus == errSecSuccess { return }
            guard dpStatus == errSecMissingEntitlement else {
                throw SecureStorageError.keychainError(dpStatus)
            }

            try storeInFile(key)
        }

        public func delete() throws {
            try? deleteFromDataProtectionKeychain()
            try? FileManager.default.removeItem(at: fileKeyURL)
            try? deleteFromLoginKeychain()
        }

        // MARK: - Backend implementations

        private func loadFromDataProtectionKeychain() throws -> SymmetricKey {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseDataProtectionKeychain as String: true,
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let keyData = result as? Data else {
                throw SecureStorageError.keychainError(status)
            }
            return SymmetricKey(data: keyData)
        }

        private func deleteFromDataProtectionKeychain() throws {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecUseDataProtectionKeychain as String: true,
            ]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw SecureStorageError.keychainError(status)
            }
        }

        private func loadFromLoginKeychain() throws -> SymmetricKey {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseDataProtectionKeychain as String: false,
            ]
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let keyData = result as? Data else {
                throw SecureStorageError.keychainError(status)
            }
            return SymmetricKey(data: keyData)
        }

        private func deleteFromLoginKeychain() throws {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecUseDataProtectionKeychain as String: false,
            ]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw SecureStorageError.keychainError(status)
            }
        }

    #endif

    private func loadFromFile() throws -> SymmetricKey {
        guard
            FileManager.default.fileExists(atPath: fileKeyURL.path),
            let keyData = try? Data(contentsOf: fileKeyURL),
            keyData.count == 32
        else {
            throw SecureStorageError.keychainError(errSecItemNotFound)
        }
        return SymmetricKey(data: keyData)
    }

    private func storeInFile(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        try FileManager.default.createDirectory(
            at: keyDirectory, withIntermediateDirectories: true)
        try keyData.write(to: fileKeyURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: fileKeyURL.path)
    }
}

/// Test-only key store. Holds the key in memory; safe across actors.
public final class InMemoryEncryptionKeyStore: EncryptionKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: SymmetricKey?

    public init(initial: SymmetricKey? = nil) {
        self.key = initial
    }

    public func load() throws -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }
        guard let key else {
            throw SecureStorageError.keychainError(errSecItemNotFound)
        }
        return key
    }

    public func store(_ key: SymmetricKey) throws {
        lock.lock()
        defer { lock.unlock() }
        self.key = key
    }

    public func delete() throws {
        lock.lock()
        defer { lock.unlock() }
        self.key = nil
    }
}
