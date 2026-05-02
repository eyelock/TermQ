import SwiftUI
import TermQShared

/// A single row in the harness sidebar list.
///
/// Shows the harness name, version, description (truncated), default vendor
/// badge, artifact count badge, and an update dot when a newer version is
/// available.
struct HarnessRowView: View {
    let harness: Harness
    @StateObject private var badgeStore = HarnessUpdateBadgeStore.shared
    /// Observed so the row re-renders when the update-availability cache
    /// populates after a `--check-updates` probe — the badge store reads
    /// through this service but doesn't republish its changes itself.
    @ObservedObject private var availability = LiveUpdateAvailabilityService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(harness.name)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)

                switch badgeStore.signal(for: harness) {
                case .versioned:
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                        .help(Strings.Harnesses.updateDotHelp)
                case .unversionedDrift:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.yellow)
                        .help(Strings.Harnesses.unversionedDriftHelp)
                case .none:
                    if case .loading = badgeStore.state(for: harness) {
                        Circle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 7, height: 7)
                    }
                }

                Spacer()

                if !harness.version.isEmpty {
                    Text(harness.version)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let description = harness.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                if !harness.defaultVendor.isEmpty {
                    vendorBadge(harness.defaultVendor)
                }

                if harness.artifacts.total > 0 {
                    artifactBadge
                }

                if let provenance = harness.installedFrom {
                    sourceBadge(provenance)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Badges

    private func vendorBadge(_ vendor: String) -> some View {
        Text(vendor)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.purple.opacity(0.7))
            .foregroundColor(.white)
            .clipShape(Capsule())
    }

    private var artifactBadge: some View {
        let counts = harness.artifacts
        var parts: [String] = []
        if counts.skills > 0 { parts.append("\(counts.skills)s") }
        if counts.agents > 0 { parts.append("\(counts.agents)a") }
        if counts.rules > 0 { parts.append("\(counts.rules)r") }
        if counts.commands > 0 { parts.append("\(counts.commands)c") }

        return Text(parts.joined(separator: " "))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }

    private func sourceBadge(_ provenance: HarnessProvenance) -> some View {
        let label: String
        switch provenance.sourceType {
        case "git":
            label = GitURLHelper.shortURL(provenance.source)
        case "local":
            label = Strings.Harnesses.sourceLocal
        case "registry":
            label = provenance.registryName ?? Strings.Harnesses.sourceMarketplace
        default:
            label = provenance.sourceType
        }

        return Text(label)
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .lineLimit(1)
    }
}
