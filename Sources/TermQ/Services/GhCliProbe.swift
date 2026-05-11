import Foundation
import TermQShared

/// Authentication status for the `gh` CLI.
///
/// Three states separate the cases the UI needs to handle:
/// - `.missing` → hide Remote tab entirely
/// - `.unauthenticated` → show Remote tab with "run `gh auth login`" empty state
/// - `.authCheckFailed` → leave previous probe state, show "couldn't verify" banner
/// - `.ready` → Remote mode fully operational
enum GhCliStatus: Equatable, Sendable {
    /// `gh` binary not found on $PATH.
    case missing
    /// Binary found, not logged in to any GitHub host.
    case unauthenticated(ghPath: String)
    /// Binary found, auth check failed due to a transient error (network, timeout).
    /// UI should surface a retry affordance but not treat user as unauthenticated.
    case authCheckFailed(ghPath: String)
    /// Binary found and authenticated. `login` is the current GitHub username.
    case ready(ghPath: String, login: String)

    var ghPath: String? {
        switch self {
        case .missing: return nil
        case .unauthenticated(let path), .authCheckFailed(let path), .ready(let path, _): return path
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var login: String? {
        if case .ready(_, let login) = self { return login }
        return nil
    }
}

/// Detects and caches `gh` CLI presence and auth status.
///
/// Mirrors `YNHDetector`: `@MainActor` singleton, async probe, cached result drives
/// sidebar Remote tab visibility. Distinguishes "not logged in" (clear message in
/// `gh auth status` stderr) from transient failures (network unreachable) so the
/// app doesn't falsely tell the user to re-auth on a flaky connection.
@MainActor
final class GhCliProbe: ObservableObject {
    static let shared = GhCliProbe()

    @Published private(set) var status: GhCliStatus = .missing

    init() {}

    // MARK: - Probe

    /// Run detection and update `status`. Call on app launch and on demand.
    func probe() async {
        guard let ghPath = findGhBinary() else {
            status = .missing
            return
        }

        // Auth check
        let authResult = try? await CommandRunner.run(
            executable: ghPath,
            arguments: ["auth", "status"]
        )

        if let result = authResult, result.didSucceed {
            // Authed. Fetch current login.
            let login = await fetchLogin(ghPath: ghPath) ?? "unknown"
            status = .ready(ghPath: ghPath, login: login)
            return
        }

        // Non-zero exit from `gh auth status`
        let stderr = authResult?.stderr ?? ""
        if isNotLoggedInError(stderr) {
            status = .unauthenticated(ghPath: ghPath)
        } else {
            // Transient failure — leave previous ready state if we had one; otherwise
            // mark as authCheckFailed so the UI can offer a retry.
            if case .ready = status {
                // Keep current ready state; a transient glitch shouldn't log the user out.
            } else {
                status = .authCheckFailed(ghPath: ghPath)
            }
        }
    }

    /// Force a fresh probe regardless of current state. Used by "Re-check" buttons.
    func reprobe() async {
        // Reset to missing so the probe runs clean.
        status = .missing
        await probe()
    }

    // MARK: - Test support

    #if DEBUG
        func setStatusForTesting(_ newStatus: GhCliStatus) {
            status = newStatus
        }
    #endif

    // MARK: - Binary discovery

    private func findGhBinary() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/gh",
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Helpers

    private func fetchLogin(ghPath: String) async -> String? {
        guard
            let result = try? await CommandRunner.run(
                executable: ghPath,
                arguments: ["api", "user", "--jq", ".login"]
            ),
            result.didSucceed
        else { return nil }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).first
    }

    /// Detect the "not logged in" error from `gh auth status` stderr.
    /// The canonical message is "You are not logged into any GitHub hosts."
    private func isNotLoggedInError(_ stderr: String) -> Bool {
        let lower = stderr.lowercased()
        return lower.contains("not logged in") || lower.contains("not logged into")
    }
}
