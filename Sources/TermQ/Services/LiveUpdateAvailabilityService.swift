import Foundation
import TermQShared

/// Production `UpdateAvailabilityService` that calls
/// `ynh ls --check-updates --format json` (or `ynh info <name> --check-updates`
/// for per-harness refresh) and caches the result.
///
/// State machine per harness:
///
/// 1. `idle` (default) — no probe has run.
/// 2. `loading` — refresh in flight.
/// 3. `fresh(at:)` — last refresh succeeded; the cached `Harness` snapshot
///    carries `version_available` etc.
/// 4. `stale` — `invalidate(harness:)` was called (e.g. after a fork) and the
///    cache is no longer trusted.
/// 5. `error(reason:)` — the most recent refresh failed; the previous
///    snapshot (if any) is preserved so the UI can fall back gracefully.
///
/// JSON fetching is injectable so the service can be unit-tested without
/// shelling out to YNH.
@MainActor
final class LiveUpdateAvailabilityService: UpdateAvailabilityService, ObservableObject {
    typealias ListFetcher = @Sendable () async throws -> Data
    typealias InfoFetcher = @Sendable (_ harnessName: String) async throws -> Data

    private struct Entry {
        var state: UpdateCheckState
        var snapshot: Harness?
    }

    @Published private var cache: [String: Entry] = [:]
    /// True while a global `refreshAll` is in flight. Drives the sidebar
    /// header spinner.
    @Published private(set) var isProbingAll: Bool = false

    private let listFetcher: ListFetcher
    private let infoFetcher: InfoFetcher
    private let now: @Sendable () -> Date

    init(
        listFetcher: @escaping ListFetcher,
        infoFetcher: @escaping InfoFetcher,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.listFetcher = listFetcher
        self.infoFetcher = infoFetcher
        self.now = now
    }

    // MARK: - UpdateAvailabilityService

    func state(forHarness id: String) -> UpdateCheckState {
        cache[id]?.state ?? .idle
    }

    func state(forInclude git: String, inHarness id: String) -> UpdateCheckState {
        // For now per-include lifecycle mirrors the harness-level lifecycle —
        // the data they share comes from the same probe. When YNH adds
        // ref_installed and per-include refresh becomes worthwhile, this
        // splits into its own cache.
        cache[id]?.state ?? .idle
    }

    func snapshot(forHarness id: String) -> Harness? {
        cache[id]?.snapshot
    }

    func refresh(harness id: String) async {
        // Use ynh info <name> --check-updates so we only re-probe the one
        // harness. The id may be namespace-qualified ("ns/repo/name") but
        // ynh info wants the bare harness name; strip any namespace.
        let name = id.split(separator: "/").last.map(String.init) ?? id
        cache[id, default: Entry(state: .idle, snapshot: nil)].state = .loading

        do {
            let data = try await infoFetcher(name)
            let response = try JSONDecoder().decode(HarnessInfoResponse.self, from: data)
            let info = response.harness
            // ynh info returns HarnessInfo (no artifacts, no nested includes
            // shape on the snapshot). For the snapshot field we keep a
            // synthesized Harness carrying the version probe results — this
            // is sufficient for hasVersionUpdate; richer fields come from
            // refreshAll's ynh ls output.
            let synthesized = Harness(
                name: info.name,
                version: info.version,
                versionAvailable: nil,
                description: info.description,
                defaultVendor: info.defaultVendor,
                path: info.path,
                installedFrom: info.installedFrom,
                artifacts: HarnessArtifactCounts(skills: 0, agents: 0, rules: 0, commands: 0),
                isPinned: info.isPinned
            )
            // Prefer the existing snapshot if refreshAll has populated richer
            // data — overwrite only the timestamp, not the snapshot itself.
            if cache[id]?.snapshot == nil {
                cache[id] = Entry(state: .fresh(at: now()), snapshot: synthesized)
            } else {
                cache[id]?.state = .fresh(at: now())
            }
        } catch {
            cache[id, default: Entry(state: .idle, snapshot: nil)].state =
                .error(reason: error.localizedDescription)
        }
    }

    func refreshAll() async {
        isProbingAll = true
        defer { isProbingAll = false }
        // Mark every known harness as loading so existing dots/banners show
        // the in-flight pulse rather than disappearing.
        for id in cache.keys {
            cache[id]?.state = .loading
        }

        do {
            let data = try await listFetcher()
            let response = try JSONDecoder().decode(HarnessListResponse.self, from: data)
            let timestamp = now()
            var rebuilt: [String: Entry] = [:]
            for harness in response.harnesses {
                rebuilt[harness.id] = Entry(
                    state: .fresh(at: timestamp), snapshot: harness)
            }
            cache = rebuilt

            // Single actionable summary so a user clicking "Update" without
            // seeing a dot can self-diagnose: pre-migration harnesses (no
            // recorded SHAs in installed.json.resolved) need one ynh update
            // to backfill before drift detection works for them.
            var withDrift = 0
            var preMigration = 0
            var clean = 0
            for harness in response.harnesses {
                if harness.hasVersionUpdate == true {
                    withDrift += 1
                    continue
                }
                let resolved = harness.includes.contains { inc in
                    inc.refInstalled?.isEmpty == false
                }
                let drifting = harness.includes.contains { inc in
                    guard let inst = inc.refInstalled, !inst.isEmpty,
                        let avail = inc.refAvailable, !avail.isEmpty
                    else { return false }
                    return inst != avail
                }
                if drifting {
                    withDrift += 1
                } else if !resolved && !harness.includes.isEmpty {
                    preMigration += 1
                } else {
                    clean += 1
                }
            }
            let total = response.harnesses.count
            let summary = "\(total) harnesses (\(withDrift) drift, \(preMigration) pre-migration, \(clean) clean)"
            TermQLogger.ui.notice("UpdateAvailability: probe complete — \(summary)")
        } catch {
            let desc = String(describing: error).prefix(200)
            TermQLogger.ui.error(
                "UpdateAvailability: refreshAll failed type=\(type(of: error)) desc=\(desc)"
            )
            for id in cache.keys {
                cache[id]?.state = .error(reason: error.localizedDescription)
            }
        }
    }

    func invalidate(harness id: String) {
        cache[id]?.state = .stale
    }
}

// MARK: - Production wiring

extension LiveUpdateAvailabilityService {
    /// Shared singleton wired to `YNHDetector.shared`. Fetchers check YNH
    /// readiness at call time so the instance can be held for the app lifetime
    /// and used as a `@StateObject` without depending on YNH being ready at
    /// construction time. If YNH is not ready the fetch throws and the service
    /// transitions to `.error`; it self-heals on the next `refreshAll()` call.
    static let shared: LiveUpdateAvailabilityService = {
        let listFetcher: ListFetcher = {
            let (ynhPath, env): (String, [String: String]) = try await MainActor.run {
                guard case .ready(let path, _, _) = YNHDetector.shared.status else {
                    throw YNHDetectionError.commandFailed(exitCode: -1, stderr: "YNH not ready")
                }
                var environ = ProcessInfo.processInfo.environment
                if let override = YNHDetector.shared.ynhHomeOverride { environ["YNH_HOME"] = override }
                return (path, environ)
            }
            let result = try await CommandRunner.run(
                executable: ynhPath,
                arguments: ["ls", "--check-updates", "--format", "json"],
                environment: env
            )
            guard result.didSucceed else {
                throw YNHDetectionError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
            }
            return Data(result.stdout.utf8)
        }
        let infoFetcher: InfoFetcher = { name in
            let (ynhPath, env): (String, [String: String]) = try await MainActor.run {
                guard case .ready(let path, _, _) = YNHDetector.shared.status else {
                    throw YNHDetectionError.commandFailed(exitCode: -1, stderr: "YNH not ready")
                }
                var environ = ProcessInfo.processInfo.environment
                if let override = YNHDetector.shared.ynhHomeOverride { environ["YNH_HOME"] = override }
                return (path, environ)
            }
            let result = try await CommandRunner.run(
                executable: ynhPath,
                arguments: ["info", name, "--check-updates", "--format", "json"],
                environment: env
            )
            guard result.didSucceed else {
                throw YNHDetectionError.commandFailed(exitCode: result.exitCode, stderr: result.stderr)
            }
            return Data(result.stdout.utf8)
        }
        return LiveUpdateAvailabilityService(listFetcher: listFetcher, infoFetcher: infoFetcher)
    }()

    /// Build a service wired to the live YNH binary discovered via
    /// `YNHDetector.shared`. Returns nil when YNH isn't ready — callers
    /// should fall back to `UnknownUpdateAvailabilityService.shared` in
    /// that window so the UI stays responsive.
    static func production(
        ynhDetector: any YNHDetectorProtocol = YNHDetector.shared
    )
        -> LiveUpdateAvailabilityService?
    {
        guard case .ready(let ynhPath, _, _) = ynhDetector.status else { return nil }

        let env: [String: String] = {
            var environ = ProcessInfo.processInfo.environment
            if let override = ynhDetector.ynhHomeOverride { environ["YNH_HOME"] = override }
            return environ
        }()

        let listFetcher: ListFetcher = {
            let result = try await CommandRunner.run(
                executable: ynhPath,
                arguments: ["ls", "--check-updates", "--format", "json"],
                environment: env
            )
            guard result.didSucceed else {
                throw YNHDetectionError.commandFailed(
                    exitCode: result.exitCode, stderr: result.stderr)
            }
            return Data(result.stdout.utf8)
        }

        let infoFetcher: InfoFetcher = { name in
            let result = try await CommandRunner.run(
                executable: ynhPath,
                arguments: ["info", name, "--check-updates", "--format", "json"],
                environment: env
            )
            guard result.didSucceed else {
                throw YNHDetectionError.commandFailed(
                    exitCode: result.exitCode, stderr: result.stderr)
            }
            return Data(result.stdout.utf8)
        }

        return LiveUpdateAvailabilityService(
            listFetcher: listFetcher, infoFetcher: infoFetcher)
    }
}
