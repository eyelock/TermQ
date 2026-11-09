import AppKit
import SwiftUI
import TermQCore
import TermQShared

/// A seat's pane with Split placement: the seat's terminal on top and, while
/// the seat has Quick Terminals, a panel beneath it. The panel has a card per
/// Quick Terminal to pick which one shows, collapses to its strip, and its
/// divider drags to resize. It goes away with the seat's last Quick Terminal.
struct WheelhouseSplitSeatBody<SeatTerminal: View>: View {
    let seatCard: TerminalCard
    let wheelhouse: Wheelhouse
    let seat: WheelhouseSeat
    @ViewBuilder let seatTerminal: () -> SeatTerminal

    @ObservedObject private var stage: WheelhouseStage = .shared
    @ObservedObject private var boardVM: BoardViewModel = .shared
    @ObservedObject private var tabManager: TabManager = BoardViewModel.shared.tabManager

    private static var stripHeight: CGFloat { 26 }

    var body: some View {
        let quick = WheelhouseCardMatcher.quickTerminals(
            in: boardVM.allTerminals, wheelhouseRoot: wheelhouse.root, seatCommand: seat.command)
        // One structure whether or not there is a panel, so the seat's own
        // terminal is never rebuilt when the first or last one comes and goes.
        GeometryReader { geometry in
            let collapsed = stage.splitCollapsed.contains(seatCard.id)
            let panelHeight =
                quick.isEmpty
                ? 0
                : Self.panelHeight(
                    total: geometry.size.height, fraction: stage.splitFraction(for: seatCard.id),
                    collapsed: collapsed, strip: Self.stripHeight)
            VStack(spacing: 0) {
                seatTerminal()
                    .frame(height: max(0, geometry.size.height - panelHeight - (quick.isEmpty ? 0 : 1)))
                if !quick.isEmpty {
                    WheelhouseSplitDivider(enabled: !collapsed) { delta in
                        let height = geometry.size.height
                        guard height > 0 else { return }
                        stage.setSplitFraction(
                            stage.splitFraction(for: seatCard.id) - delta / height, for: seatCard.id)
                    }
                    panel(quick: quick, collapsed: collapsed)
                        .frame(height: panelHeight)
                }
            }
        }
    }

    /// The panel's height: its strip when collapsed, else its share of the
    /// pane with room for a few lines, never more than the pane.
    static func panelHeight(total: CGFloat, fraction: CGFloat, collapsed: Bool, strip: CGFloat) -> CGFloat {
        let available = max(0, total - 1)
        if collapsed { return min(strip, available) }
        return min(available, max(strip * 3, total * fraction))
    }

    @ViewBuilder
    private func panel(quick: [TerminalCard], collapsed: Bool) -> some View {
        let selectedId = stage.splitQuickTerminal(for: seatCard.id, among: quick.map(\.id))
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    stage.toggleSplitCollapsed(seatCard.id)
                } label: {
                    Image(systemName: collapsed ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help(collapsed ? Strings.Wheelhouse.showQuickTerminals : Strings.Wheelhouse.hideQuickTerminals)
                ForEach(quick, id: \.id) { card in
                    quickCard(card, selected: card.id == selectedId)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: Self.stripHeight)
            .background(Color.primary.opacity(0.04))

            if !collapsed, let selected = quick.first(where: { $0.id == selectedId }) {
                TerminalHostView(
                    card: selected,
                    onExit: {},
                    onBell: { tabManager.markStageBell(selected.id) },
                    focusPolicy: .whenBecomingFocused,
                    isFocusedPane: false
                )
                .id(selected.id)
            }
        }
    }

    /// One Quick Terminal in the strip: click to show it, right-click to
    /// close it.
    private func quickCard(_ card: TerminalCard, selected: Bool) -> some View {
        let number = WheelhouseCardMatcher.quickTerminalNumber(card) ?? 0
        let ringing = tabManager.needsAttention.contains(card.id)
        return Button {
            stage.selectSplitQuickTerminal(card.id, for: seatCard.id)
            tabManager.clearAttention(card.id)
        } label: {
            HStack(spacing: 4) {
                WheelhouseQuickTerminalBadge(
                    number: number, running: boardVM.activeSessionCards.contains(card.id), onStage: false)
                Text(Strings.Wheelhouse.quickTerminalTitle(number))
                    .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
            }
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        ringing
                            ? Color.orange.opacity(0.22)
                            : (selected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06))))
        }
        .buttonStyle(.plain)
        .help(Strings.Wheelhouse.quickTerminalHelp(number, seat.name))
        .contextMenu {
            Button(role: .destructive) {
                stage.closeQuickTerminal(card)
            } label: {
                Label(Strings.Wheelhouse.closeTerminal, systemImage: WheelhouseMenuIcon.closeTerminal)
                    .labelStyle(.titleAndIcon)
            }
        }
    }
}

/// The divider above a split panel: a hairline with a taller grab area.
/// Reports each drag step as points moved down since the last step.
struct WheelhouseSplitDivider: View {
    let enabled: Bool
    let onDrag: (CGFloat) -> Void

    @State private var lastTranslation: CGFloat = 0
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .overlay {
                // Always there, so a pushed cursor is always popped; only
                // active while the panel is open.
                Color.clear
                    .frame(height: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        let wanted = inside && enabled
                        guard wanted != hovering else { return }
                        hovering = wanted
                        if wanted { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                guard enabled else { return }
                                onDrag(value.translation.height - lastTranslation)
                                lastTranslation = value.translation.height
                            }
                            .onEnded { _ in lastTranslation = 0 }
                    )
            }
            .onChange(of: enabled) { _, isEnabled in
                if !isEnabled && hovering {
                    hovering = false
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if hovering { NSCursor.pop() }
            }
            .zIndex(1)
    }
}
