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
            guard action != .closeTerminal else { return wheelhouseStage.remove(card) }
            wheelhouseStage.show(card)
        }
    }

    /// Outside the Wheelhouse view, seat terminals stay out of the general
    /// tab strip and the main panel: they live on the stage.
    var nonSeatTabCards: [TerminalCard] {
        WheelhouseCardMatcher.generalTabCards(viewModel.tabCards, wheelhouseEnabled: wheelhouseTabEnabled)
    }

    var selectedNonSeatCard: TerminalCard? {
        guard let card = viewModel.selectedCard else { return nil }
        guard wheelhouseTabEnabled, WheelhouseCardMatcher.isSeatCard(card) else { return card }
        return nil
        return card
    }
}
