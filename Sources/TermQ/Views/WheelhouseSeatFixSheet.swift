import AppKit
import SwiftUI
import TermQShared

/// A seat to fix: which Wheelhouse and seat, for `.sheet(item:)`.
struct WheelhouseSeatFixRequest: Identifiable {
    let wheelhouse: Wheelhouse
    let seat: WheelhouseSeat
    var id: String { wheelhouse.root + "/" + seat.command }
}

/// What a seat marked "action required" needs, one issue per row, each with
/// the step that fixes it. Opens when a seat with issues is clicked, in place
/// of a launch that would fail.
struct WheelhouseSeatFixSheet: View {
    let request: WheelhouseSeatFixRequest
    let onSeatAction: (Wheelhouse, WheelhouseSeat, WheelhouseSeatAction) -> Void

    @ObservedObject private var store: WheelhouseStore = .shared
    @ObservedObject private var harnessRepo: HarnessRepository = .shared
    @Environment(\.dismiss) private var dismiss

    private var wheelhouse: Wheelhouse { request.wheelhouse }
    private var seat: WheelhouseSeat { request.seat }

    private var issues: [WheelhouseSeatIssue] {
        store.issues(for: seat, in: wheelhouse, installed: harnessRepo.isInstalled(name: seat.command))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: WheelhouseMenuIcon.actionRequired)
                    .foregroundColor(.orange)
                Text(Strings.Wheelhouse.fixTitle(seat.name))
                    .font(.headline)
            }
            if issues.isEmpty {
                Text(Strings.Wheelhouse.fixAllClear)
                    .foregroundColor(.secondary)
            }
            ForEach(issues, id: \.self) { issue in
                issueRow(issue)
            }
            Divider()
            HStack {
                Button(Strings.Wheelhouse.openAnyway) {
                    dismiss()
                    onSeatAction(wheelhouse, seat, .open)
                }
                Spacer()
                Button(Strings.Common.close) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    @ViewBuilder
    private func issueRow(_ issue: WheelhouseSeatIssue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch issue {
            case .notInstalled:
                row(Strings.Wheelhouse.issueNotInstalled, Strings.Wheelhouse.issueNotInstalledDetail(seat.command))
                Button {
                    dismiss()
                    onSeatAction(wheelhouse, seat, .install)
                } label: {
                    Label(Strings.Wheelhouse.install, systemImage: WheelhouseMenuIcon.install)
                }
            case .delegatesNotCommitted(let paths):
                row(
                    Strings.Wheelhouse.issueNotCommitted(Self.names(paths)),
                    Strings.Wheelhouse.issueNotCommittedDetail)
                HStack {
                    Button {
                        PathActions.copyPathname(Self.commitCommand(root: wheelhouse.root, paths: paths))
                    } label: {
                        Label(Strings.Wheelhouse.copyCommitCommand, systemImage: WheelhouseMenuIcon.copy)
                    }
                    Button {
                        dismiss()
                        onSeatAction(wheelhouse, seat, .quickTerminal)
                    } label: {
                        Label(Strings.Sidebar.newTerminal, systemImage: LaunchMenuIcon.quickTerminal)
                    }
                }
            case .delegatesMissing(let paths):
                row(Strings.Wheelhouse.issueMissing(Self.names(paths)), Strings.Wheelhouse.issueMissingDetail)
                Button {
                    PathActions.revealInFinder(
                        path: WheelhouseSeatHealth.harnessDirectory(root: wheelhouse.root, seat: seat))
                } label: {
                    Label(Strings.Wheelhouse.revealInFinder, systemImage: WheelhouseMenuIcon.revealInFinder)
                }
            case .launchFailed(let message):
                row(Strings.Wheelhouse.issueLaunchFailed, message)
                Button {
                    store.recordLaunchFailure(nil, for: seat, in: wheelhouse)
                    dismiss()
                    onSeatAction(wheelhouse, seat, .open)
                } label: {
                    Label(Strings.Wheelhouse.tryAgain, systemImage: LaunchMenuIcon.quickLaunch)
                }
            }
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
    }

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    /// "io, titan" from "harnesses/io", "harnesses/titan".
    static func names(_ paths: [String]) -> String {
        paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
    }

    /// The command that commits only the delegates, for the human to run: a
    /// suggestion, so TermQ never commits on their behalf.
    static func commitCommand(root: String, paths: [String]) -> String {
        let quotedPaths = paths.map(shellQuoted).joined(separator: " ")
        let repo = shellQuoted(root)
        let message = shellQuoted("Add \(names(paths))")
        return "git -C \(repo) add -- \(quotedPaths) && git -C \(repo) commit -m \(message) -- \(quotedPaths)"
    }

    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Hover text for a seat's warning icon: each issue, then how to fix.
    static func tooltip(for issues: [WheelhouseSeatIssue], seat: WheelhouseSeat) -> String {
        let lines = issues.map { issue -> String in
            switch issue {
            case .notInstalled: return Strings.Wheelhouse.issueNotInstalled
            case .delegatesNotCommitted(let paths): return Strings.Wheelhouse.issueNotCommitted(names(paths))
            case .delegatesMissing(let paths): return Strings.Wheelhouse.issueMissing(names(paths))
            case .launchFailed(let message): return Strings.Wheelhouse.issueLaunchFailed + ": " + message
            }
        }
        return (lines + [Strings.Wheelhouse.actionRequiredHelp]).joined(separator: "\n")
    }
}
