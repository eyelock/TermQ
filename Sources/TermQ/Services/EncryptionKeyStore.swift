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

/// Live key store. In RELEASE builds this is the macOS Data Protection Keychain
/// (with a one-time migration from the legacy Login Keychain). In TERMQ_DEBUG_BUILD
/// builds it falls back to a 0o600-permissioned file alongside the encrypted secrets,
/// because the ad-hoc-signed debug app cannot use the modern keychain.
public struct LiveEncryptionKeyStore: EncryptionKeyStore {
    public let service: String
    public let account: String
    /// Directory used in DEBUG builds for the `.enc-key` file. Ignored in RELEASE.
    public let debugKeyDirectory: URL

    public init(service: String, account: String, debugKeyDirectory: URL) {
        self.service = service
        self.account = account
        self.debugKeyDirectory = debugKeyDirectory
    }

    #if TERMQ_DEBUG_BUILD

        private var debugKeyURL: URL {
            debugKeyDirectory.appendingPathComponent(".enc-key")
        }

        public func load() throws -> SymmetricKey {
            guard
                FileManager.default.fileExists(atPath: debugKeyURL.path),
                let keyData = try? Data(contentsOf: debugKeyURL),
                keyData.count == 32
            else {
                throw SecureStorageError.keychainError(errSecItemNotFound)
            }
            return SymmetricKey(data: keyData)
        }

        public func store(_ key: SymmetricKey) throws {
            let keyData = key.withUnsafeBytes { Data($0) }
            try FileManager.default.createDirectory(
                at: debugKeyDirectory, withIntermediateDirectories: true)
            try keyData.write(to: debugKeyURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: debugKeyURL.path)
        }

        public func delete() throws {
            try? FileManager.default.removeItem(at: debugKeyURL)
        }

    #else

        public func load() throws -> SymmetricKey {
            // Modern Data Protection Keychain (bundle ID + Team ID access control,
            // survives rebuilds without prompting).
            let modernQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseDataProtectionKeychain as String: true,
            ]

            var result: AnyObject?
            let modernStatus = SecItemCopyMatching(modernQuery as CFDictionary, &result)

            if modernStatus == errSecSuccess, let keyData = result as? Data {
                return SymmetricKey(data: keyData)
            }

            // One-time migration from legacy Login Keychain (binary-hash ACL).
            let legacyQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]

            result = nil
            let legacyStatus = SecItemCopyMatching(legacyQuery as CFDictionary, &result)

            guard legacyStatus == errSecSuccess, let keyData = result as? Data else {
                throw SecureStorageError.keychainError(modernStatus)
            }

            let key = SymmetricKey(data: keyData)
            try store(key)  // promote into Data Protection Keychain
            try? deleteLegacy()  // best-effort cleanup
            return key
        }

        public func store(_ key: SymmetricKey) throws {
            let keyData = key.withUnsafeBytes { Data($0) }
            try? delete()

            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: keyData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
                kSecUseDataProtectionKeychain as String: true,
            ]

            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw SecureStorageError.keychainError(status)
            }
        }

        public func delete() throws {
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

        private func deleteLegacy() throws {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]

            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw SecureStorageError.keychainError(status)
            }
        }

    #endif
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
