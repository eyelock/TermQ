import Foundation

/// Validates AppProfile values against runtime environment (debug builds only)
public enum AppProfileValidator {
    /// Validate that AppProfile.Current matches actual bundle identifier
    /// Only runs in DEBUG builds to avoid performance impact in production
    public static func validateAtStartup() {
        #if DEBUG
            guard let actualBundleId = Bundle.main.bundleIdentifier else {
                print("⚠️ WARNING: No bundle identifier found in Bundle.main")
                return
            }

            if actualBundleId != AppProfile.Current.bundleIdentifier {
                print("⚠️ WARNING: AppProfile bundle identifier mismatch!")
                print("  Expected: \(AppProfile.Current.bundleIdentifier)")
                print("  Actual: \(actualBundleId)")
                print("  This indicates AppProfile.swift is out of sync with Info.plist")
            } else {
                print("✅ AppProfile validated: \(actualBundleId)")
            }
        #endif
    }
}
