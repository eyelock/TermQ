import Foundation
import TermQShared

/// Service that fetches vendor metadata by running `ynh vendors --format json`.
@MainActor
final class VendorService: ObservableObject {
    static let shared = VendorService()

    @Published private(set) var vendors: [Vendor] = []
    @Published private(set) var isLoading = false

    private let ynhDetector: any YNHDetectorProtocol

    private convenience init() {
        self.init(ynhDetector: YNHDetector.shared)
    }

    init(ynhDetector: any YNHDetectorProtocol) {
        self.ynhDetector = ynhDetector
    }

    func refresh() async {
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
            let output = try await YNHDetector.runCommand(
                ynhPath,
                args: ["vendors", "--format", "json"],
                environment: env
            )
            let data = Data(output.utf8)
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
