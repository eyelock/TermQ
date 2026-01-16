import Foundation
import TermQCore

// MARK: - Environment Variable Resolution

extension TerminalSessionManager {
    /// Thread-safe container for passing values across concurrency boundaries
    private final class SecretValueBox: @unchecked Sendable {
        var value: String?
    }

    /// Resolves terminal-specific environment variables, including secrets.
    /// For secrets, fetches values from SecureStorage synchronously using a semaphore.
    func resolveTerminalEnvironmentVariables(_ card: TerminalCard) -> [String: String] {
        var result: [String: String] = [:]

        for variable in card.environmentVariables {
            if variable.isSecret {
                // Fetch secret value synchronously using semaphore and thread-safe box
                let semaphore = DispatchSemaphore(value: 0)
                let box = SecretValueBox()
                let secretId = "terminal-\(card.id.uuidString)-\(variable.id.uuidString)"

                Task.detached {
                    box.value = try? await SecureStorage.shared.retrieveSecret(id: secretId)
                    semaphore.signal()
                }

                // Wait with timeout to avoid deadlock
                let waitResult = semaphore.wait(timeout: .now() + 2.0)
                if waitResult == .success, let value = box.value {
                    result[variable.key] = value
                }
            } else {
                result[variable.key] = variable.value
            }
        }

        return result
    }

    /// Builds the complete environment for a terminal by merging:
    /// 1. Global environment variables
    /// 2. Terminal-specific environment variables (overrides global)
    func buildUserEnvironmentVariables(_ card: TerminalCard) -> [String: String] {
        // Start with global variables
        var result = GlobalEnvironmentManager.shared.resolvedVariablesSync()

        // Override with terminal-specific variables
        let terminalVars = resolveTerminalEnvironmentVariables(card)
        for (key, value) in terminalVars {
            result[key] = value
        }

        return result
    }
}
