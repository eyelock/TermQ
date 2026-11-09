import SwiftUI
import TermQCore
import TermQShared

// MARK: - Window menu (⌘1–9)

extension ContentView {
    /// Snapshot of open terminals for the Window menu's jump list — the five
    /// most-recently-active terminals, most recent first (an MRU switcher), so
    /// ⌘1 is the current terminal, ⌘2 the one before, and so on. Terminals not
    /// activated yet this session fall to the end in board order. Republished
    /// whenever the board or activation order changes. On the Wheelhouse
    /// stage, the open seats instead.
    var windowMenu: WindowMenuModel {
        if showsWheelhouseStage { return stageWindowMenu }
        let active = viewModel.board.activeCards
        let recencyRank = Dictionary(
            viewModel.recentlyActiveCardIds.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first })
        let ordered = active.sorted {
            let lhs = recencyRank[$0.id] ?? Int.max
            let rhs = recencyRank[$1.id] ?? Int.max
            return lhs != rhs ? lhs < rhs : $0.orderIndex < $1.orderIndex
        }
        let items = ordered.prefix(5).map {
            OpenTerminalItem(
                id: $0.id,
                title: $0.title.isEmpty ? Strings.Menu.terminalFallbackTitle : $0.title,
                isFavourite: $0.isFavourite)
        }
        return WindowMenuModel(
            openTerminals: Array(items),
            totalOpen: active.count,
            jumpToTerminal: { id in
                guard let card = viewModel.board.activeCards.first(where: { $0.id == id })
                else { return }
                isZoomed = false
                viewModel.selectCard(card)
            })
    }

    /// On the stage, ⌘1–9 jump to the open seats in the tab strip, left to
    /// right: bringing one on stage, or focusing it if it's there.
    var stageWindowMenu: WindowMenuModel {
        let cards = wheelhouseStore.openSeatCards(
            in: viewModel.allTerminals, root: wheelhouseStage.scopeRoot(in: wheelhouseStore.wheelhouses),
            stage: wheelhouseStage, running: viewModel.activeSessionCards, ringing: tabManager.needsAttention)
        let items = WheelhouseStore.stageMenuItems(cards, wheelhouses: wheelhouseStore.wheelhouses)
        return WindowMenuModel(
            openTerminals: items,
            // Seats past nine are reached from the strip: "All Terminals…"
            // opens the board's palette, which doesn't list seats.
            totalOpen: items.count,
            jumpToTerminal: { id in
                guard let card = viewModel.allTerminals.first(where: { $0.id == id }) else { return }
                wheelhouseStage.show(id)
                viewModel.selectCard(card)
            })
    }
}
