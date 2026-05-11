import SwiftUI
import TermQShared

/// A single row in the harness sidebar list.
///
/// Shows the harness name, version, description (truncated), default vendor
/// badge, artifact count badge, and an update dot when a newer version is
/// available.
struct HarnessRowView: View {
    let harness: Harness
    var isActiveTerminal: Bool = false
    @StateObject private var badgeStore = HarnessUpdateBadgeStore.shared
    /// Observed so the row re-renders when the update-availability cache
    /// populates after a `--check-updates` probe — the badge store reads
    /// through this service but doesn't republish its changes itself.
    @ObservedObject private var availability = LiveUpdateAvailabilityService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(harness.name)
                    .font(.system(.body, weight: isActiveTerminal ? .semibold : .medium))
                    .lineLimit(1)
                    .foregroundColor(harness.isBrokenLocalFork ? .secondary : .primary)

                if harness.isBrokenLocalFork {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .help(harness.brokenReason ?? Strings.Harnesses.brokenForkHelp)
                } else {
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
                }

                Spacer()

                if !harness.version.isEmpty {
                    Text(harness.version)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if harness.isBrokenLocalFork {
                if let reason = harness.brokenReason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.85))
                        .lineLimit(2)
                } else {
                    Text(Strings.Harnesses.brokenForkHelp)
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.85))
                        .lineLimit(2)
                }
            } else if let description = harness.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                if harness.isBrokenLocalFork {
                    brokenBadge
                }

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

    private var brokenBadge: some View {
        Text(Strings.Harnesses.brokenForkBadge)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.red.opacity(0.7))
            .foregroundColor(.white)
            .clipShape(Capsule())
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

    @ViewBuilder
    private func sourceBadge(_ provenance: HarnessProvenance) -> some View {
        // Forks are pointer-installed local harnesses with a `forked_from`
        // origin recorded. Surface them with a fork icon + the upstream
        // shortname so the row stands apart from a hand-built local harness.
        if let origin = provenance.forkedFrom {
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9))
                Text(forkLabel(for: origin))
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            .foregroundColor(.secondary)
            .help(Strings.Harnesses.forkedFromHelp(originDescription(origin)))
        } else {
            Text(plainSourceLabel(for: provenance))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private func plainSourceLabel(for provenance: HarnessProvenance) -> String {
        switch provenance.sourceType {
        case "git":
            return GitURLHelper.shortURL(provenance.source)
        case "local":
            return Strings.Harnesses.sourceLocal
        case "registry":
            return provenance.registryName ?? Strings.Harnesses.sourceMarketplace
        default:
            return provenance.sourceType
        }
    }

    /// Compact "Fork of <upstream>" label using the upstream registry name
    /// when available, falling back to a short git URL.
    private func forkLabel(for origin: ForkOrigin) -> String {
        if let registry = origin.registryName, !registry.isEmpty {
            return Strings.Harnesses.forkOf(registry)
        }
        return Strings.Harnesses.forkOf(GitURLHelper.shortURL(origin.source))
    }

    /// Full upstream description used in the row tooltip.
    private func originDescription(_ origin: ForkOrigin) -> String {
        var parts: [String] = []
        if let registry = origin.registryName, !registry.isEmpty {
            parts.append(registry)
        }
        parts.append(GitURLHelper.shortURL(origin.source))
        if let version = origin.version, !version.isEmpty {
            parts.append("@\(version)")
        }
        return parts.joined(separator: " / ")
    }
}
