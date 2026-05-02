import AppKit
import SwiftUI
import TermQShared

/// Dependency section for the harness detail pane: includes and delegates
/// with resolved status, clickable git links, and pick pills.
///
/// Shows composed dependency data when available (from `ynd compose`),
/// falling back to basic data from `ynh ls` while detail loads.
struct HarnessDetailDependencyView: View {
    let harness: Harness
    let detail: HarnessDetail?
    var updateSignal: HarnessUpdateSignal = .none

    /// True when this dependency row corresponds to upstream content that
    /// drifted without a version bump. Matched by `path` against the
    /// harness-level `unversionedDrift` list.
    private func isDrifted(path: String?) -> Bool {
        guard case .unversionedDrift(let drifted) = updateSignal,
            let path, !path.isEmpty
        else { return false }
        return drifted.contains { $0.path == path }
    }

    @ViewBuilder
    private func resolutionBadge(resolved: Bool, drifted: Bool) -> some View {
        if drifted {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(.yellow)
                .help(Strings.Harnesses.unversionedDriftHelp)
        } else if resolved {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(.green)
                .help(Strings.Harnesses.detailResolved)
        } else {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(.orange)
                .help(Strings.Harnesses.detailUnresolved)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.Harnesses.detailDependencies)
                .font(.headline)

            if let detail {
                composedDependencies(detail.composition)
            } else {
                basicDependencies
            }
        }
    }

    /// Whether there are any dependencies to show.
    var hasDependencies: Bool {
        if let detail {
            return !detail.composition.includes.isEmpty || !detail.composition.delegatesTo.isEmpty
        }
        return !harness.includes.isEmpty || !harness.delegatesTo.isEmpty
    }

    // MARK: - Composed Dependencies

    private func composedDependencies(_ comp: HarnessComposition) -> some View {
        Group {
            if !comp.includes.isEmpty {
                Text(Strings.Harnesses.detailIncludes(comp.includes.count))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(comp.includes.indices, id: \.self) { idx in
                    composedIncludeCard(comp.includes[idx])
                }
            }

            if !comp.delegatesTo.isEmpty {
                Text(Strings.Harnesses.detailDelegates(comp.delegatesTo.count))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(comp.delegatesTo.indices, id: \.self) { idx in
                    composedDelegateCard(comp.delegatesTo[idx])
                }
            }
        }
    }

    private func composedIncludeCard(_ include: ComposedInclude) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)

                GitSourceLabel(source: include.git)

                if let ref = include.ref, !ref.isEmpty {
                    Text("@\(ref)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                resolutionBadge(
                    resolved: include.resolved,
                    drifted: isDrifted(path: include.path)
                )

                Spacer()

                GitActionButtons(source: include.git, path: include.path)
            }

            if let path = include.path, !path.isEmpty {
                subpathRow(path)
            }

            if let picks = include.pick, !picks.isEmpty {
                picksBlock(picks, source: include.git, ref: include.ref)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func composedDelegateCard(_ delegate: ComposedDelegate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)

                GitSourceLabel(source: delegate.git)

                if let ref = delegate.ref, !ref.isEmpty {
                    Text("@\(ref)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                GitActionButtons(source: delegate.git, path: delegate.path)
            }

            if let path = delegate.path, !path.isEmpty {
                subpathRow(path)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Basic Dependencies (fallback)

    private var basicDependencies: some View {
        Group {
            if !harness.includes.isEmpty {
                Text(Strings.Harnesses.detailIncludes(harness.includes.count))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(harness.includes.indices, id: \.self) { idx in
                    basicIncludeCard(harness.includes[idx])
                }
            }

            if !harness.delegatesTo.isEmpty {
                Text(Strings.Harnesses.detailDelegates(harness.delegatesTo.count))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(harness.delegatesTo.indices, id: \.self) { idx in
                    basicDelegateCard(harness.delegatesTo[idx])
                }
            }
        }
    }

    private func basicIncludeCard(_ include: HarnessInclude) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)

                GitSourceLabel(source: include.git)

                if let ref = include.ref, !ref.isEmpty {
                    Text("@\(ref)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                GitActionButtons(source: include.git, path: include.path)
            }

            if let path = include.path, !path.isEmpty {
                subpathRow(path)
            }

            if let picks = include.pick, !picks.isEmpty {
                picksBlock(picks, source: include.git, ref: include.ref)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func basicDelegateCard(_ delegate: HarnessDelegate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)

                GitSourceLabel(source: delegate.git)

                if let ref = delegate.ref, !ref.isEmpty {
                    Text("@\(ref)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                GitActionButtons(source: delegate.git, path: delegate.path)
            }

            if let path = delegate.path, !path.isEmpty {
                subpathRow(path)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Shared Card Components

    private func subpathRow(_ path: String) -> some View {
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

    private func picksBlock(_ picks: [String], source: String, ref: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Strings.Harnesses.detailPicks(picks.count))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.leading, 20)

            FlowLayout(spacing: 4) {
                ForEach(picks, id: \.self) { pick in
                    GitPickPill(pick: pick, source: source)
                }
            }
            .padding(.leading, 20)
        }
    }
}

// MARK: - Git Source Helpers

/// Clickable git source label — links to browser for remote URLs, selectable text for local paths.
struct GitSourceLabel: View {
    let source: String

    var body: some View {
        if let url = GitURLHelper.browserURL(for: source) {
            Link(destination: url) {
                Text(GitURLHelper.shortURL(source))
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
struct GitActionButtons: View {
    let source: String
    let path: String?

    var body: some View {
        HStack(spacing: 4) {
            if let url = GitURLHelper.browserURL(for: source, path: path) {
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
}

/// A clickable pick pill — opens in browser for remote, reveals in Finder for local.
struct GitPickPill: View {
    let pick: String
    let source: String

    var body: some View {
        if let url = GitURLHelper.browserURL(for: source, path: pick) {
            Link(destination: url) {
                pillLabel
            }
            .pointingHandCursor()
            .help(Strings.Harnesses.openInBrowser)
        } else if source.hasPrefix("/") {
            Button {
                let fullPath = "\(source)/\(pick)"
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: fullPath)
            } label: {
                pillLabel
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(Strings.Harnesses.revealInFinder)
        } else {
            pillLabel
        }
    }

    private var pillLabel: some View {
        Text(pick)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.1))
            .foregroundColor(.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
