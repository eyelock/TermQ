import CryptoKit
import Foundation
import Security
import TermQShared

/// Errors that can occur during secure storage operations
public enum SecureStorageError: LocalizedError {
    case keychainError(OSStatus)
    case encryptionFailed
    case decryptionFailed
    case invalidData
    case fileOperationFailed(Error)
    case directoryCreationFailed(Error)
    case directoryNotWritable

    public var errorDescription: String? {
        switch self {
        case .keychainError(let status):
            return "Keychain error: \(SecCopyErrorMessageString(status, nil) ?? "Unknown" as CFString)"
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data. The encryption key may have changed."
        case .invalidData:
            return "Invalid data format"
        case .fileOperationFailed(let error):
            return "File operation failed: \(error.localizedDescription)"
        case .directoryCreationFailed(let error):
            return "Failed to create directory: \(error.localizedDescription)"
        case .directoryNotWritable:
            return "Directory is not writable"
        }
    }
}

/// Secure storage service for managing encrypted secrets
/// Uses macOS Keychain for encryption key and file-based storage for encrypted data
public actor SecureStorage {
    public static let shared = SecureStorage()

    // MARK: - Constants

    private let keychainService = AppProfile.Services.keychainService
    private let keychainAccount = "encryption-key"
    private let secretsFileName = "secrets.enc"

    // MARK: - State

    private var cachedSecrets: [String: String]?

    // MARK: - Public Interface

    /// Gets the current config directory URL (uses central DataDirectoryManager)
    public func getConfigDirectory() -> URL {
        DataDirectoryManager.url
    }

    /// Checks if an encryption key exists in Keychain
    public func hasEncryptionKey() -> Bool {
        do {
            _ = try getEncryptionKey()
            return true
        } catch {
            return false
        }
    }

    /// Stores a secret value
    public func storeSecret(id: String, value: String) async throws {
        var secrets = try await loadSecrets()
        secrets[id] = value
        try await saveSecrets(secrets)
    }

    /// Retrieves a secret value
    public func retrieveSecret(id: String) async throws -> String? {
        let secrets = try await loadSecrets()
        return secrets[id]
    }

    /// Deletes a secret
    public func deleteSecret(id: String) async throws {
        var secrets = try await loadSecrets()
        secrets.removeValue(forKey: id)
        try await saveSecrets(secrets)
    }

    /// Lists all secret IDs
    public func listSecretIds() async throws -> [String] {
        let secrets = try await loadSecrets()
        return Array(secrets.keys)
    }

    /// Resets the encryption key (WARNING: This deletes all secrets!)
    public func resetEncryptionKey() throws {
        // Delete the key from Keychain
        try deleteKeychainKey()
        // Delete the secrets file
        let secretsURL = getConfigDirectory().appendingPathComponent(secretsFileName)
        try? FileManager.default.removeItem(at: secretsURL)
        // Clear cache
        cachedSecrets = nil
    }

    /// Exports all secrets as an encrypted blob for backup
    public func exportSecrets() async throws -> Data {
        let secretsURL = getConfigDirectory().appendingPathComponent(secretsFileName)
        if FileManager.default.fileExists(atPath: secretsURL.path) {
            return try Data(contentsOf: secretsURL)
        }
        return Data()
    }

    /// Imports secrets from an encrypted blob (from backup)
    /// Note: Requires the same encryption key to decrypt
    public func importSecrets(_ data: Data) async throws {
        guard !data.isEmpty else { return }

        // Verify we can decrypt the data
        let key = try getOrCreateEncryptionKey()
        _ = try decrypt(data, using: key)

        // Write the data
        let secretsURL = getConfigDirectory().appendingPathComponent(secretsFileName)
        try ensureConfigDirectoryExists()
        try data.write(to: secretsURL)
        cachedSecrets = nil
    }

    /// Clears the in-memory cache, forcing a reload from disk on next access
    public func clearCache() {
        cachedSecrets = nil
    }

    // MARK: - Private Helpers

    private func ensureConfigDirectoryExists() throws {
        do {
            try DataDirectoryManager.ensureDirectoryExists()
        } catch {
            throw SecureStorageError.directoryCreationFailed(error)
        }
    }

    // MARK: - Keychain Operations

    private func getOrCreateEncryptionKey() throws -> SymmetricKey {
        // Try to get existing key
        if let existingKey = try? getEncryptionKey() {
            return existingKey
        }

        // Generate new key
        let newKey = SymmetricKey(size: .bits256)
        try storeEncryptionKey(newKey)
        return newKey
    }

    private func getEncryptionKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let keyData = result as? Data else {
            throw SecureStorageError.keychainError(status)
        }

        return SymmetricKey(data: keyData)
    }

    private func storeEncryptionKey(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }

        // Delete any existing key first
        try? deleteKeychainKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureStorageError.keychainError(status)
        }
    }

    private func deleteKeychainKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]

        let status = SecItemDelete(query as CFDictionary)
        // Ignore "item not found" error
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStorageError.keychainError(status)
        }
    }

    // MARK: - Encryption/Decryption

    private func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else {
                throw SecureStorageError.encryptionFailed
            }
            return combined
        } catch {
            throw SecureStorageError.encryptionFailed
        }
    }

    private func decrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw SecureStorageError.decryptionFailed
        }
    }

    // MARK: - File Operations

    private func loadSecrets() async throws -> [String: String] {
        // Return cached if available
        if let cached = cachedSecrets {
            return cached
        }

        let secretsURL = getConfigDirectory().appendingPathComponent(secretsFileName)

        // Return empty if file doesn't exist
        guard FileManager.default.fileExists(atPath: secretsURL.path) else {
            cachedSecrets = [:]
            return [:]
        }

        do {
            let encryptedData = try Data(contentsOf: secretsURL)
            let key = try getOrCreateEncryptionKey()
            let decryptedData = try decrypt(encryptedData, using: key)

            let secrets = try JSONDecoder().decode([String: String].self, from: decryptedData)
            cachedSecrets = secrets
            return secrets
        } catch let error as SecureStorageError {
            throw error
        } catch {
            throw SecureStorageError.fileOperationFailed(error)
        }
    }

    private func saveSecrets(_ secrets: [String: String]) async throws {
        try ensureConfigDirectoryExists()

        let secretsURL = getConfigDirectory().appendingPathComponent(secretsFileName)

        do {
            let jsonData = try JSONEncoder().encode(secrets)
            let key = try getOrCreateEncryptionKey()
            let encryptedData = try encrypt(jsonData, using: key)

            try encryptedData.write(to: secretsURL, options: .atomic)

            // Set restrictive permissions on the file
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: secretsURL.path)

            cachedSecrets = secrets
        } catch let error as SecureStorageError {
            throw error
        } catch {
            throw SecureStorageError.fileOperationFailed(error)
        }
    }
}
