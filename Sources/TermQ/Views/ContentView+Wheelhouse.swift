import AppKit
import SwiftUI
import TermQCore
import TermQShared

// MARK: - Wheelhouse

extension ContentView {
    /// While the Wheelhouses tab (or focus mode) is up, the main panel is the
    /// seat stage only: no other terminals, no general tab strip.
    var showsWheelhouseStage: Bool {
        wheelhouseTabEnabled && (sidebarState.selectedTab == .wheelhouses || wheelhouseStage.focusMode)
    }

    var seatAction: (Wheelhouse, WheelhouseSeat, WheelhouseSeatAction) -> Void {
        { wheelhouse, seat, action in
            guard let card = launchCoordinator.perform(action, seat: seat, in: wheelhouse) else { return }
            switch action {
            case .closeTerminal: wheelhouseStage.remove(card)
            // Sent to a running seat, the stage stays as it is. A seat that
            // isn't running only starts once its pane is up, so bring it up.
            case .send where TerminalSessionManager.shared.hasActiveSession(for: card): break
            default: wheelhouseStage.show(card)
            }
        }
    }

    /// The seat of the stage's focused pane: its own, or a Quick Terminal's
    /// parent. What the stage's shortcuts act on.
    var focusedStageSeat: (wheelhouse: Wheelhouse, seat: WheelhouseSeat)? {
        WheelhouseStore.shared.owningSeat(ofCardId: wheelhouseStage.focused, in: viewModel.allTerminals)
    }

    /// ⌘T: on the stage, a Quick Terminal for the focused seat (nothing when
    /// no seat is focused, such as the inbox: a general terminal would be
    /// hidden by the stage); elsewhere a new terminal.
    func quickNewTerminalOrSeatQuickTerminal() {
        guard showsWheelhouseStage else {
            viewModel.quickNewTerminal()
            return
        }
        if let found = focusedStageSeat {
            seatAction(found.wheelhouse, found.seat, .quickTerminal)
        } else {
            NSSound.beep()
        }
    }

    /// A stage pane fills the window: the sidebar steps aside too.
    var stageZoomed: Bool {
        showsWheelhouseStage && wheelhouseStage.zoomed.map(wheelhouseStage.isOnStage) == true
    }

    /// ⌥⌘Z: on the stage, zoom the focused pane or come back; elsewhere the
    /// board's zoom.
    func toggleZoomOrStageZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if showsWheelhouseStage {
                wheelhouseStage.toggleZoom()
            } else {
                isZoomed.toggle()
            }
        }
    }

    /// Outside the Wheelhouse view, seat terminals stay out of the general
    /// tab strip and the main panel: they live on the stage.
    var nonSeatTabCards: [TerminalCard] {
        WheelhouseCardMatcher.generalTabCards(viewModel.tabCards, wheelhouseEnabled: wheelhouseTabEnabled)
    }

    var selectedNonSeatCard: TerminalCard? {
        guard let card = viewModel.selectedCard else { return nil }
        guard wheelhouseTabEnabled, WheelhouseCardMatcher.isWheelhouseCard(card) else { return card }
        return nil
    }

    /// The stage selects seat cards, which the general view hides. Entering
    /// the stage remembers the terminal you were in; leaving puts you back in
    /// it, unless you picked another general terminal while on the stage.
    func wheelhouseStageVisibilityChanged(showing: Bool) {
        if showing {
            wheelhouseStage.cardBeforeStage = selectedNonSeatCard?.id
            return
        }
        // Zoom belongs to the stage: coming back shows the whole stage.
        wheelhouseStage.exitZoom()
        defer { wheelhouseStage.cardBeforeStage = nil }
        guard selectedNonSeatCard == nil else { return }
        if let id = wheelhouseStage.cardBeforeStage,
            let card = viewModel.allTerminals.first(where: { $0.id == id && $0.deletedAt == nil })
        {
            viewModel.selectCard(card)
        } else if viewModel.selectedCard != nil {
            viewModel.deselectCard()
        }
    }
}
