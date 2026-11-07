import SwiftUI
import TermQCore
import TermQShared

/// Shown above the harness detail page when it was opened from a Wheelhouse
/// seat: whose harness this is, that edits apply when the seat restarts, and,
/// while the seat is running, a button to restart it now.
struct WheelhouseSeatHarnessBanner: View {
    let wheelhouse: Wheelhouse
    let seat: WheelhouseSeat
    /// Asks the seat to hand off (types the handoff request into its session).
    let onHandoff: (TerminalCard) -> Void
    /// Restarts the seat as a fresh session, so it wakes on its handoff notes.
    let onRestart: (TerminalCard) -> Void

    @ObservedObject private var boardVM: BoardViewModel = .shared
    @State private var handoffAsked = false

    private var runningCard: TerminalCard? {
        guard
            let card = WheelhouseCardMatcher.card(
                in: boardVM.allTerminals, wheelhouseRoot: wheelhouse.root, seatCommand: seat.command),
            boardVM.activeSessionCards.contains(card.id)
        else { return nil }
        return card
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "steeringwheel")
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(Strings.Wheelhouse.seatHarnessTitle(seat.name, wheelhouse.title))
                    .font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let card = runningCard {
                Button {
                    onHandoff(card)
                    handoffAsked = true
                } label: {
                    Label(Strings.Wheelhouse.stepHandoff(seat.name), systemImage: "moon.zzz")
                }
                .controlSize(.small)
                Button {
                    onRestart(card)
                    handoffAsked = false
                } label: {
                    Label(Strings.Wheelhouse.stepRestart(seat.name), systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(!handoffAsked)
                .help(Strings.Wheelhouse.restartSeatHelp)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.10))
    }

    private var message: String {
        guard runningCard != nil else { return Strings.Wheelhouse.seatHarnessIdle(seat.name) }
        return handoffAsked
            ? Strings.Wheelhouse.seatHarnessHandingOff(seat.name)
            : Strings.Wheelhouse.seatHarnessRunning(seat.name)
    }
}
