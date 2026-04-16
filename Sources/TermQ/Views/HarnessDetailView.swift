import AppKit
import SwiftUI
import TermQShared

/// Changes the cursor to a pointing hand on hover.
private struct PointingHandCursor: ViewModifier {
    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

extension View {
    fileprivate func pointingHandCursor() -> some View {
        modifier(PointingHandCursor())
    }
}

/// Minimal detail view for a selected harness (Phase 2 — header only).
///
/// Shows harness identity, provenance, path, and artifact summary.
/// Full composition detail (skills, agents, hooks, etc.) ships in Phase 3.
struct HarnessDetailView: View {
    let harness: Harness
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                Divider()
                infoSection
                Divider()
                artifactSection

                if !harness.includes.isEmpty || !harness.delegatesTo.isEmpty {
                    Divider()
                    dependencySection
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(harness.name)
                    .font(.title)
                    .fontWeight(.bold)

                if !harness.version.isEmpty {
                    Text(harness.version)
                        .font(.title3)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(Strings.Harnesses.closeDetail)
            }

            if let description = harness.description, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                if !harness.defaultVendor.isEmpty {
                    vendorBadge(harness.defaultVendor)
                }

                if let provenance = harness.installedFrom {
                    sourceBadge(provenance)
                }
            }
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Harnesses.detailInfo)
                .font(.headline)

            HStack(alignment: .top, spacing: 8) {
                Text(Strings.Harnesses.detailPath)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .trailing)
                Text(harness.path)
                    .font(.body)
                    .textSelection(.enabled)
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: harness.path)
                } label: {
                    Image(systemName: "folder")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .pointingHandCursor()
                .help(Strings.Harnesses.revealInFinder)
            }

            if let provenance = harness.installedFrom {
                labeledRow(Strings.Harnesses.detailSource, value: provenance.source)

                if let subpath = provenance.path, !subpath.isEmpty {
                    labeledRow(Strings.Harnesses.detailSubpath, value: subpath)
                }

                labeledRow(Strings.Harnesses.detailInstalledAt, value: provenance.installedAt)
            }
        }
    }

    // MARK: - Artifacts

    private var artifactSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Harnesses.detailArtifacts)
                .font(.headline)

            HStack(spacing: 12) {
                artifactCount(Strings.Harnesses.detailSkills, count: harness.artifacts.skills)
                artifactCount(Strings.Harnesses.detailAgents, count: harness.artifacts.agents)
                artifactCount(Strings.Harnesses.detailRules, count: harness.artifacts.rules)
                artifactCount(Strings.Harnesses.detailCommands, count: harness.artifacts.commands)
            }

            if harness.artifacts.total == 0 && !harness.includes.isEmpty {
                Text(Strings.Harnesses.detailArtifactsFromIncludes)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Dependencies

    private var dependencySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.Harnesses.detailDependencies)
                .font(.headline)

            if !harness.includes.isEmpty {
                Text(Strings.Harnesses.detailIncludes(harness.includes.count))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(harness.includes.indices, id: \.self) { idx in
                    includeCard(harness.includes[idx])
                }
            }

            if !harness.delegatesTo.isEmpty {
                Text(Strings.Harnesses.detailDelegates(harness.delegatesTo.count))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(harness.delegatesTo.indices, id: \.self) { idx in
                    delegateCard(harness.delegatesTo[idx])
                }
            }
        }
    }

    private func includeCard(_ include: HarnessInclude) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Source row: icon + short name + action buttons
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)

                gitSourceLabel(include.git)

                if let ref = include.ref, !ref.isEmpty {
                    Text("@\(ref)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                gitActionButtons(include.git, path: include.path)
            }

            // Subpath
            if let path = include.path, !path.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 20)
            }

            // Picked artifacts
            if let picks = include.pick, !picks.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Strings.Harnesses.detailPicks(picks.count))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)

                    FlowLayout(spacing: 4) {
                        ForEach(picks, id: \.self) { pick in
                            pickPill(pick, source: include.git, ref: include.ref)
                        }
                    }
                    .padding(.leading, 20)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func delegateCard(_ delegate: HarnessDelegate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)

                gitSourceLabel(delegate.git)

                if let ref = delegate.ref, !ref.isEmpty {
                    Text("@\(ref)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                gitActionButtons(delegate.git, path: delegate.path)
            }

            if let path = delegate.path, !path.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 20)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Git Source Helpers

    /// Display label for a git source — clickable for remote URLs.
    private func gitSourceLabel(_ source: String) -> some View {
        Group {
            if let url = browserURL(for: source) {
                Link(destination: url) {
                    Text(shortGitURL(source))
                        .font(.system(size: 12, weight: .medium))
                        .underline()
                }
                .pointingHandCursor()
            } else {
                Text(source)
                    .font(.system(size: 12, weight: .medium))
                    .textSelection(.enabled)
            }
        }
    }

    /// Action buttons for a git source: open in browser and/or reveal in Finder.
    private func gitActionButtons(_ source: String, path: String?) -> some View {
        HStack(spacing: 4) {
            if let url = browserURL(for: source, path: path) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .pointingHandCursor()
                .help(Strings.Harnesses.openInBrowser)
            }

            if source.hasPrefix("/") {
                Button {
                    let fullPath = path.map { "\(source)/\($0)" } ?? source
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: fullPath)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .pointingHandCursor()
                .help(Strings.Harnesses.revealInFinder)
            }
        }
    }

    /// Construct a browser URL from a git source like `github.com/user/repo`.
    private func browserURL(for source: String, path: String? = nil) -> URL? {
        guard !source.hasPrefix("/"), !source.hasPrefix(".") else { return nil }

        var urlString = "https://\(source)"
        if let path, !path.isEmpty {
            urlString += "/tree/HEAD/\(path)"
        }
        return URL(string: urlString)
    }

    /// A pick pill — clickable link for remote sources, plain text for local.
    @ViewBuilder
    private func pickPill(_ pick: String, source: String, ref: String?) -> some View {
        if let url = browserURL(for: source, path: pick) {
            Link(destination: url) {
                pickPillLabel(pick)
            }
            .pointingHandCursor()
            .help(Strings.Harnesses.openInBrowser)
        } else if source.hasPrefix("/") {
            Button {
                let fullPath = "\(source)/\(pick)"
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: fullPath)
            } label: {
                pickPillLabel(pick)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(Strings.Harnesses.revealInFinder)
        } else {
            pickPillLabel(pick)
        }
    }

    private func pickPillLabel(_ pick: String) -> some View {
        Text(pick)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.1))
            .foregroundColor(.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Helpers

    private func labeledRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    private func artifactCount(_ label: String, count: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(count > 0 ? .primary : .secondary)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 50)
    }

    private func vendorBadge(_ vendor: String) -> some View {
        Text(vendor)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.purple.opacity(0.2))
            .foregroundColor(.purple)
            .clipShape(Capsule())
    }

    private func sourceBadge(_ provenance: HarnessProvenance) -> some View {
        let label: String
        switch provenance.sourceType {
        case "git":
            label = shortGitURL(provenance.source)
        case "local":
            label = Strings.Harnesses.sourceLocal
        case "registry":
            label = provenance.registryName ?? Strings.Harnesses.sourceRegistry
        default:
            label = provenance.sourceType
        }

        return Text(label)
            .font(.system(size: 11))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }

    private func shortGitURL(_ url: String) -> String {
        guard !url.hasPrefix("/"), !url.hasPrefix(".") else { return url }
        let parts = url.split(separator: "/", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]) : url
    }
}
