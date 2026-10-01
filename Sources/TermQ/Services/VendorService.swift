import Foundation
import TermQShared

/// Service that fetches vendor metadata by running `ynh vendors --format json`.
@MainActor
final class VendorService: ObservableObject {
    static let shared = VendorService()

    @Published private(set) var vendors: [Vendor] = []
    @Published private(set) var isLoading = false

    /// Vendor ids whose CLI can resume a previous session, per the installed YNH.
    var resumableVendorIDs: Set<String> {
        Set(vendors.filter(\.supportsResume).map(\.vendorID))
    }

    /// Whether `refresh()` has completed at least once since launch.
    private(set) var hasLoaded = false
    private var initialLoad: Task<Void, Never>?

    private let ynhDetector: any YNHDetectorProtocol
    private let commandRunner: any YNHCommandRunner

    private convenience init() {
        self.init(ynhDetector: YNHDetector.shared)
    }

    init(
        ynhDetector: any YNHDetectorProtocol,
        commandRunner: any YNHCommandRunner = LiveYNHCommandRunner()
    ) {
        self.ynhDetector = ynhDetector
        self.commandRunner = commandRunner
    }

    /// Loads vendor metadata once if nothing has been loaded yet.
    ///
    /// Nothing refreshes vendors at app start — only a launch request or one
    /// of the harness sheets does — so a card relaunched straight after the
    /// app opens would otherwise see an empty list. Concurrent callers share
    /// the same first load rather than each spawning `ynh vendors`.
    func ensureLoaded() async {
        if hasLoaded { return }
        if let initialLoad {
            await initialLoad.value
            return
        }
        let task = Task { await refresh() }
        initialLoad = task
        await task.value
        initialLoad = nil
    }

    func refresh() async {
        defer { hasLoaded = true }
        guard case .ready(let ynhPath, _, _) = ynhDetector.status else {
            vendors = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        var env = ProcessInfo.processInfo.environment
        if let override = ynhDetector.ynhHomeOverride {
            env["YNH_HOME"] = override
        }

        do {
            let result = try await commandRunner.run(
                executable: ynhPath,
                arguments: ["vendors", "--format", "json"],
                environment: env
            )
            guard result.didSucceed else {
                throw YNHDetectionError.commandFailed(
                    exitCode: result.exitCode,
                    stderr: result.stderr
                )
            }
            let data = Data(result.stdout.utf8)
            vendors = try JSONDecoder().decode([Vendor].self, from: data)
        } catch {
            if TermQLogger.fileLoggingEnabled {
                TermQLogger.session.warning("VendorService: ynh vendors failed: \(error.localizedDescription)")
            } else {
                TermQLogger.session.warning("VendorService: ynh vendors failed")
            }
            vendors = []
        }
    }
}
