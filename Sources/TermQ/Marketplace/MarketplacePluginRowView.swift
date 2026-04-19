import SwiftUI

/// A single plugin row inside `MarketplaceDetailView`.
///
/// - If YNH is ready: shows "Add to Harness" button.
/// - If YNH is not installed: shows "Copy Install Command" button.
/// - Skills are shown when eagerly loaded; an expand button triggers lazy load for external sources.
struct MarketplacePluginRowView: View {
    let plugin: MarketplacePlugin
    let isYNHReady: Bool
    let isLoadingSkills: Bool
    let onAddToHarness: () -> Void
    let onExpandSkills: () -> Void

    @State private var showSkills = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title row
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(plugin.name)
                            .font(.body).fontWeight(.medium)
                        if let version = plugin.version, !version.isEmpty {
                            Text(version)
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    if let desc = plugin.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption).foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                    chipsRow
                }
                Spacer(minLength: 8)
                actionButton
            }

            // Skills
            skillsSection
        }
    }

    // MARK: - Chips

    @ViewBuilder
    private var chipsRow: some View {
        let chips: [String] = [plugin.category].compactMap { $0 } + plugin.tags
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundColor(.secondary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        if isYNHReady {
            Button(Strings.Marketplace.pluginAddToHarness) { onAddToHarness() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        } else {
            Button {
                let installCmd = "/plugin install \(plugin.name)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(installCmd, forType: .string)
            } label: {
                Label(Strings.Marketplace.pluginCopyInstallCommand, systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(Strings.Marketplace.pluginCopyInstallCommandHelp)
        }
    }

    // MARK: - Skills

    @ViewBuilder
    private var skillsSection: some View {
        switch plugin.skillsState {
        case .eager:
            if !plugin.picks.isEmpty {
                DisclosureGroup(isExpanded: $showSkills) {
                    FlowLayout(spacing: 4) {
                        ForEach(plugin.picks, id: \.self) { skill in
                            Text(skill)
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.1))
                                .foregroundColor(.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text(artifactSummary(plugin.picks))
                        .font(.caption).foregroundColor(.secondary)
                }
            } else if plugin.source.type.isExternal {
                Button {
                    showSkills = true
                    onExpandSkills()
                } label: {
                    Label(Strings.Marketplace.pluginLoadArtifacts, systemImage: "chevron.right")
                        .font(.caption).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

        case .pending:
            Button {
                showSkills = true
                onExpandSkills()
            } label: {
                Label(Strings.Marketplace.pluginLoadArtifacts, systemImage: "chevron.right")
                    .font(.caption).foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(Strings.Marketplace.pluginLoadingArtifacts).font(.caption).foregroundColor(.secondary)
            }

        case .failed(let msg):
            Text(Strings.Marketplace.pluginArtifactsUnavailable(msg))
                .font(.caption2).foregroundColor(.secondary)
                .lineLimit(2)
        }
    }

    // MARK: - Helpers

    private func artifactSummary(_ picks: [String]) -> String {
        var counts: [String: Int] = [:]
        for pick in picks {
            let type = String(pick.prefix(while: { $0 != "/" }))
            counts[type, default: 0] += 1
        }
        let order = ["skills", "agents", "commands", "rules"]
        let labels: [String] = order.compactMap { key in
            guard let count = counts[key], count > 0 else { return nil }
            return "\(count) \(key.dropLast(count == 1 ? 1 : 0))"
        }
        return labels.isEmpty ? "\(picks.count) artifacts" : labels.joined(separator: " · ")
    }
}
