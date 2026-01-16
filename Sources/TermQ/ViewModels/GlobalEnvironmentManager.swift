import Foundation
import TermQCore

/// Storage representation for environment variable metadata (without secret values)
private struct StoredEnvironmentVariable: Codable {
    let id: UUID
    var key: String
    var value: String  // Empty for secrets
    var isSecret: Bool
}

/// Manages global environment variables
/// Non-secret values are stored in UserDefaults, secret values in SecureStorage
@MainActor
public class GlobalEnvironmentManager: ObservableObject {
    public static let shared = GlobalEnvironmentManager()

    private let storageKey = "GlobalEnvironmentVariables"

    @Published public private(set) var variables: [EnvironmentVariable] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public var error: Error?

    private init() {
        Task {
            await load()
        }
    }

    // MARK: - Public Interface

    /// Loads variables from storage
    public func load() async {
        isLoading = true
        error = nil

        do {
            let stored = loadStoredVariables()
            var loaded: [EnvironmentVariable] = []

            for storedVar in stored {
                if storedVar.isSecret {
                    // Fetch secret value from SecureStorage
                    let secretValue =
                        try await SecureStorage.shared.retrieveSecret(
                            id: "global-\(storedVar.id.uuidString)") ?? ""
                    loaded.append(
                        EnvironmentVariable(
                            id: storedVar.id,
                            key: storedVar.key,
                            value: secretValue,
                            isSecret: true
                        ))
                } else {
                    loaded.append(
                        EnvironmentVariable(
                            id: storedVar.id,
                            key: storedVar.key,
                            value: storedVar.value,
                            isSecret: false
                        ))
                }
            }

            variables = loaded
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Adds a new environment variable
    public func addVariable(_ variable: EnvironmentVariable) async throws {
        // Check for duplicate keys
        if variables.contains(where: { $0.key.uppercased() == variable.key.uppercased() }) {
            throw GlobalEnvironmentError.duplicateKey(variable.key)
        }

        // Validate key
        guard variable.isValidKey else {
            throw GlobalEnvironmentError.invalidKey(variable.key)
        }

        if variable.isSecret {
            // Store secret value in SecureStorage
            try await SecureStorage.shared.storeSecret(
                id: "global-\(variable.id.uuidString)",
                value: variable.value
            )
        }

        variables.append(variable)
        saveStoredVariables()
    }

    /// Updates an existing environment variable
    public func updateVariable(_ variable: EnvironmentVariable) async throws {
        guard let index = variables.firstIndex(where: { $0.id == variable.id }) else {
            throw GlobalEnvironmentError.variableNotFound(variable.id)
        }

        let oldVariable = variables[index]

        // Check for duplicate keys (excluding self)
        if variables.contains(where: {
            $0.id != variable.id && $0.key.uppercased() == variable.key.uppercased()
        }) {
            throw GlobalEnvironmentError.duplicateKey(variable.key)
        }

        // Validate key
        guard variable.isValidKey else {
            throw GlobalEnvironmentError.invalidKey(variable.key)
        }

        // Handle secret status change
        if oldVariable.isSecret && !variable.isSecret {
            // Was secret, now not - delete from SecureStorage
            try await SecureStorage.shared.deleteSecret(id: "global-\(variable.id.uuidString)")
        } else if variable.isSecret {
            // Is secret (new or updated) - store in SecureStorage
            try await SecureStorage.shared.storeSecret(
                id: "global-\(variable.id.uuidString)",
                value: variable.value
            )
        }

        variables[index] = variable
        saveStoredVariables()
    }

    /// Deletes an environment variable
    public func deleteVariable(id: UUID) async throws {
        guard let index = variables.firstIndex(where: { $0.id == id }) else {
            throw GlobalEnvironmentError.variableNotFound(id)
        }

        let variable = variables[index]

        if variable.isSecret {
            try await SecureStorage.shared.deleteSecret(id: "global-\(id.uuidString)")
        }

        variables.remove(at: index)
        saveStoredVariables()
    }

    /// Returns resolved key-value pairs for all variables (fetches secret values)
    public func resolvedVariables() async throws -> [String: String] {
        var result: [String: String] = [:]

        for variable in variables {
            if variable.isSecret {
                if let secretValue = try await SecureStorage.shared.retrieveSecret(
                    id: "global-\(variable.id.uuidString)")
                {
                    result[variable.key] = secretValue
                }
            } else {
                result[variable.key] = variable.value
            }
        }

        return result
    }

    /// Checks if a key already exists (case-insensitive)
    public func keyExists(_ key: String, excludingId: UUID? = nil) -> Bool {
        variables.contains {
            $0.key.uppercased() == key.uppercased() && $0.id != excludingId
        }
    }

    /// Returns resolved key-value pairs synchronously from cached values.
    /// For secrets, uses the value stored in memory (loaded at init).
    /// This is safe to call from synchronous contexts.
    public func resolvedVariablesSync() -> [String: String] {
        var result: [String: String] = [:]
        for variable in variables {
            result[variable.key] = variable.value
        }
        return result
    }

    // MARK: - Private Helpers

    private func loadStoredVariables() -> [StoredEnvironmentVariable] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([StoredEnvironmentVariable].self, from: data)
        } catch {
            return []
        }
    }

    private func saveStoredVariables() {
        let stored = variables.map { variable in
            StoredEnvironmentVariable(
                id: variable.id,
                key: variable.key,
                value: variable.isSecret ? "" : variable.value,
                isSecret: variable.isSecret
            )
        }

        do {
            let data = try JSONEncoder().encode(stored)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            self.error = error
        }
    }
}

/// Errors for GlobalEnvironmentManager operations
public enum GlobalEnvironmentError: LocalizedError {
    case duplicateKey(String)
    case invalidKey(String)
    case variableNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .duplicateKey(let key):
            return "An environment variable with key '\(key)' already exists"
        case .invalidKey(let key):
            return "'\(key)' is not a valid environment variable name"
        case .variableNotFound:
            return "Environment variable not found"
        }
    }
}
