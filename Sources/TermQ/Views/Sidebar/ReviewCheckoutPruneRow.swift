import SwiftUI
import TermQShared

/// One review checkout in a Prune sheet: its PR, why it will be kept or
/// removed, and anything worth knowing first (changes, a folder git forgot).
struct ReviewCheckoutPruneRow: View {
    let candidate: FocusWorktreeCandidate

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: candidate.canPrune ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(candidate.canPrune ? .green : .orange)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.prNumber.map { "#\($0)" } ?? candidate.displayName)
                    .font(.subheadline)
                Text(candidate.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                let notes = Self.notes(for: candidate)
                if !notes.isEmpty {
                    Text(notes.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            Text(candidate.canPrune ? Strings.RemotePRs.pruneRemove : Strings.RemotePRs.pruneKeep)
                .font(.caption)
                .foregroundColor(candidate.canPrune ? .red : .secondary)
        }
        .padding(.vertical, 2)
    }

    static func notes(for candidate: FocusWorktreeCandidate) -> [String] {
        var notes: [String] = []
        switch candidate.prState {
        case .open: notes.append(Strings.RemotePRs.pruneReasonPROpen)
        case .closed: notes.append(Strings.RemotePRs.pruneReasonPRClosed)
        case .unknown: break
        }
        if candidate.hasOpenTerminal { notes.append(Strings.RemotePRs.pruneReasonInUse) }
        if candidate.isDirty { notes.append(Strings.RemotePRs.pruneReasonDirty) }
        if candidate.isOrphan { notes.append(Strings.RemotePRs.pruneReasonOrphan) }
        return notes
    }
}
