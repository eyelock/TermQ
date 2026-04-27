import Foundation

/// Protocol covering the `YNHDetector` surface that `HarnessRepository` and
/// `VendorService` depend on — enabling dependency injection and test isolation.
///
/// The protocol is `@MainActor` to match `YNHDetector` itself.
@MainActor
protocol YNHDetectorProtocol: AnyObject {
    /// Current detection status for the YNH toolchain.
    var status: YNHStatus { get }

    /// The `$YNH_HOME` override configured in settings, or `nil` for default.
    var ynhHomeOverride: String? { get }
}
