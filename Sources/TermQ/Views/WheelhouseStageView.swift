import AppKit
import SwiftUI
import TermQCore
import TermQShared

/// The main panel while the Wheelhouses tab is open: up to three seat
/// terminals side by side, the seats that need the human above them, and
/// nothing that isn't a Wheelhouse seat.
struct WheelhouseStageView: View {
    var onSeatAction: (Wheelhouse, WheelhouseSeat, WheelhouseSeatAction) -> Void

    @ObservedObject private var stage: WheelhouseStage = .shared
    @ObservedObject private var store: WheelhouseStore = .shared
    @ObservedObject private var boardVM: BoardViewModel = .shared
    @ObservedObject private var tabManager: TabManager = BoardViewModel.shared.tabManager
    @State private var clickMonitor = StagePaneClickMonitor()
    /// The pane header a dragged seat is over, to highlight it.
    @State private var dropTarget: UUID?

    /// Only the selected Wheelhouse's seats in focus mode or when one is picked.
    private var scopeRoot: String? { stage.scopeRoot(in: store.wheelhouses) }

    private var seatCards: [TerminalCard] {
        store.seatCards(in: boardVM.allTerminals, root: scopeRoot)
    }

    /// What can be on the stage: a seat's card, one of its Quick Terminals,
    /// or the inbox.
    private enum StageEntry: Identifiable {
        case card(TerminalCard)
        case inbox

        var id: UUID {
            switch self {
            case .card(let card): return card.id
            case .inbox: return WheelhouseStage.inboxEntry
            }
        }
    }

    private var stageEntries: [StageEntry] {
        // Split: a Quick Terminal sits beneath its seat, not on the stage.
        let cards = WheelhouseStore.paneCards(
            store.stageCards(in: boardVM.allTerminals, root: scopeRoot), placement: stage.quickTerminalPlacement,
            all: boardVM.allTerminals, wheelhouses: store.wheelhouses)
        return stage.visible.compactMap { id in
            if id == WheelhouseStage.inboxEntry { return .inbox }
            return cards.first { $0.id == id }.map(StageEntry.card)
        }
    }

    private var stageCards: [TerminalCard] {
        stageEntries.compactMap { entry in
            if case .card(let card) = entry { return card }
            return nil
        }
    }

    /// The inbox for the Wheelhouse in view (every Wheelhouse's when none is picked).
    private var inboxItems: [(wheelhouse: Wheelhouse, item: WheelhouseInboxItem)] {
        store.inboxItems(root: scopeRoot)
    }

    /// A run of tabs in the strip: one seat group of one Wheelhouse.
    private struct StripGroup {
        let wheelhouse: Wheelhouse
        let cards: [TerminalCard]
    }

    /// The tab bar: every open seat (running, waiting on you, or on stage),
    /// by Wheelhouse in sidebar order, then desk first, then crew, standing and
    /// workers, each in roster order, grouped so the strip can draw dividers
    /// between.
    private var openSeatGroups: [StripGroup] {
        var groups: [StripGroup] = []
        for card in openSeatCards {
            guard let found = store.seat(for: card) else { continue }
            if let last = groups.last, last.wheelhouse.root == found.wheelhouse.root,
                store.seat(for: last.cards[0])?.seat.group.sortOrder == found.seat.group.sortOrder
            {
                groups[groups.count - 1] = StripGroup(wheelhouse: last.wheelhouse, cards: last.cards + [card])
            } else {
                groups.append(StripGroup(wheelhouse: found.wheelhouse, cards: [card]))
            }
        }
        return groups
    }

    /// Whether seats from more than one Wheelhouse are open, so tabs and
    /// panes say which Wheelhouse each seat is from.
    private var showsWheelhouseNames: Bool {
        Set(openSeatGroups.map(\.wheelhouse.root)).count > 1
    }

    /// Every open seat (running, waiting on you, or on stage) in strip order:
    /// what ⌘1–9 jump to.
    private var openSeatCards: [TerminalCard] {
        store.openSeatCards(
            in: boardVM.allTerminals, root: scopeRoot, stage: stage, running: boardVM.activeSessionCards,
            ringing: tabManager.needsAttention)
    }

    /// Seats that rang, oldest first, including ones already on stage: a chip
    /// for one of those focuses its pane.
    private var attentionQueue: [TerminalCard] {
        let cards = seatCards
        let order = WheelhouseAttention.queue(
            candidates: cards.map(\.id), since: tabManager.attentionSince)
        return order.compactMap { id in cards.first { $0.id == id } }
    }

    /// The pane zoomed to fill the window, while it is on stage.
    private var zoomedCard: TerminalCard? {
        stage.zoomed.flatMap { id in stageCards.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let zoomedCard {
                pane(zoomedCard)
            } else {
                topBar
                Divider()
                needsYouRail
                Divider()
                if stageEntries.isEmpty {
                    emptyStage
                } else {
                    panes
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(shortcuts)
        .onChange(of: stageCards.map(\.id)) { _, ids in stage.healZoom(visible: Set(ids)) }
        .onChange(of: stage.quickTerminalPlacement) { moveQuickTerminalsIntoPanels() }
        .onDisappear { clickMonitor.stop() }
        .onAppear {
            clickMonitor.start { cardId in
                guard let pane = stage.paneClicked(cardId, host: splitHostId(of: cardId), tabs: tabManager),
                    let card = stageCards.first(where: { $0.id == pane })
                else { return }
                focus(card)
            } onTypeInPane: { cardId in
                stage.paneTyped(cardId, host: splitHostId(of: cardId), tabs: tabManager)
            }
            moveQuickTerminalsIntoPanels()
            stage.prune(keeping: Set(boardVM.allTerminals.map(\.id)).union([WheelhouseStage.inboxEntry]))
            if let focused = stage.focused, let card = stageCards.first(where: { $0.id == focused }) {
                boardVM.selectCard(card)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "steeringwheel")
                .foregroundColor(.accentColor)
            Text(store.wheelhouses.first { $0.root == scopeRoot }?.title ?? Strings.Wheelhouse.stageTitle)
                .font(.system(size: 13, weight: .semibold))
            if !openSeatCards.isEmpty {
                Divider().frame(height: 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        let groups = openSeatGroups
                        let named = showsWheelhouseNames
                        ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                            let startsWheelhouse =
                                index == 0 || groups[index - 1].wheelhouse.root != group.wheelhouse.root
                            if index > 0 {
                                Divider().frame(height: startsWheelhouse && named ? 18 : 14).padding(.horizontal, 2)
                            }
                            if named && startsWheelhouse {
                                wheelhouseLabel(group.wheelhouse)
                            }
                            ForEach(group.cards, id: \.id) { card in
                                openSeatChip(card)
                            }
                        }
                    }
                }
            } else {
                Spacer()
            }
            Button {
                stage.focusMode.toggle()
            } label: {
                Label(
                    stage.focusMode ? Strings.Wheelhouse.exitFocus : Strings.Wheelhouse.enterFocus,
                    systemImage: stage.focusMode
                        ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .controlSize(.small)
            .help(Strings.Wheelhouse.focusHelp)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private func openSeatChip(_ card: TerminalCard) -> some View {
        let seat = store.seat(for: card)
        let ringing = tabManager.needsAttention.contains(card.id)
        let onStage = stage.isOnStage(card.id)
        let focused = stage.focused == card.id
        return Button {
            show(card)
        } label: {
            HStack(spacing: 5) {
                WheelhouseSeatDot(
                    kind: ringing ? .needsYou : (boardVM.activeSessionCards.contains(card.id) ? .open : .closed))
                Text(seat?.seat.name ?? card.title)
                    .font(.system(size: 11.5, weight: focused ? .semibold : .regular))
                if stage.isPinned(card.id) {
                    Image(systemName: "pin.fill").font(.system(size: 8))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(onStage ? Color.accentColor.opacity(focused ? 0.32 : 0.18) : Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .help(chipHelp(card))
        .draggable(WheelhouseStage.dragPayload(card.id))
        .contextMenu { seatCardMenu(card) }
    }

    /// The right-click menu for a seat card, the same on its tab and on its
    /// pane header.
    private func seatCardMenu(_ card: TerminalCard) -> some View {
        seatCardMenuItems(card).labelStyle(.titleAndIcon)
    }

    @ViewBuilder
    private func seatCardMenuItems(_ card: TerminalCard) -> some View {
        if let found = store.seat(for: card) {
            WheelhouseSeatActionItems(
                wheelhouse: found.wheelhouse, seat: found.seat, hasTerminal: true,
                showsShortcuts: stage.focused == card.id, onSeatAction: onSeatAction)
            Divider()
        }
        WheelhouseKeepOnStageToggle(cardId: card.id, showsShortcut: stage.focused == card.id)
        zoomMenuItem(card)
        if store.parentSeat(of: card) != nil {
            Button(role: .destructive) {
                stage.closeQuickTerminal(card)
            } label: {
                Label(Strings.Wheelhouse.closeTerminal, systemImage: WheelhouseMenuIcon.closeTerminal)
            }
        }
    }

    /// Hover text for a seat chip: who it is, what kind of seat, what it's
    /// for, and what it's on.
    private func chipHelp(_ card: TerminalCard) -> String {
        guard let found = store.seat(for: card) else { return Strings.Wheelhouse.bringOnStage }
        let seat = found.seat
        var lines: [String] = []
        let role = Strings.Wheelhouse.roleLabel(for: seat)
        lines.append(
            [seat.name, role, Strings.Wheelhouse.groupLabel(seat.group)].compactMap { $0 }.joined(separator: " · "))
        if let mandate = seat.mandate { lines.append(mandate) }
        if let bead = store.currentBead(for: seat, in: found.wheelhouse) {
            lines.append("\(bead.id): \(bead.title)")
        }
        lines.append(Strings.Wheelhouse.bringOnStage)
        return lines.joined(separator: "\n\n")
    }

    // MARK: - Needs you

    private var needsYouRail: some View {
        let queue = attentionQueue
        let shown = Array(queue.prefix(3))
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Strings.Wheelhouse.needsYou.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(queue.isEmpty ? .secondary : .orange)
                Text(queue.isEmpty ? Strings.Wheelhouse.nobodyWaiting : "⌘J")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }
            .frame(width: 92, alignment: .leading)

            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(spacing: 8) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, card in
                        attentionChip(card, first: index == 0, now: context.date)
                    }
                }
            }
            if queue.count > shown.count {
                Text(Strings.Wheelhouse.moreWaiting(queue.count - shown.count))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            inboxChip
        }
        .padding(.horizontal, 12)
        .frame(height: queue.isEmpty ? 34 : 50)
        .background(queue.isEmpty ? Color.clear : Color.orange.opacity(0.08))
        .animation(.easeOut(duration: 0.2), value: queue.map(\.id))
    }

    private func attentionChip(_ card: TerminalCard, first: Bool, now: Date) -> some View {
        let found = store.seat(for: card)
        let since = tabManager.attentionSince[card.id] ?? now
        let role = found.flatMap { Strings.Wheelhouse.roleLabel(for: $0.seat) }
        let bead = found.flatMap { store.currentBead(for: $0.seat, in: $0.wheelhouse) }
        return Button {
            show(card)
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(found?.seat.name ?? card.title)
                            .font(.system(size: 12, weight: .bold))
                        Text([role, Self.age(since: since, now: now)].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Text(bead?.title ?? Strings.Wheelhouse.rangTheBell)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .frame(width: 230, height: 38, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(first ? 0.22 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(first ? 0.9 : 0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    static func age(since: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(since)))
        if seconds < 60 { return Strings.Wheelhouse.justNow }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }

    // MARK: - Panes

    private static let dividerWidth: CGFloat = 1
    private static let minPaneWidth: CGFloat = 240

    /// Panes side by side, each its weighted share of the width; drag a
    /// divider to resize the two panes beside it, double-click it for equal.
    private var panes: some View {
        GeometryReader { geometry in
            let cards = stageEntries
            let available = max(0, geometry.size.width - CGFloat(max(0, cards.count - 1)) * Self.dividerWidth)
            let weights = cards.map { stage.weight(for: $0.id) }
            let widths = WheelhousePaneSizing.widths(weights: weights, available: available)
            HStack(spacing: 0) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    if index > 0 {
                        WheelhousePaneDivider(width: Self.dividerWidth) { delta in
                            let resized = WheelhousePaneSizing.resized(
                                left: weights[index - 1], right: weights[index],
                                weightPerPoint: WheelhousePaneSizing.weightPerPoint(
                                    weights: weights, available: available),
                                delta: delta, minWidth: Self.minPaneWidth)
                            stage.setWeights(
                                (cards[index - 1].id, resized.left), (card.id, resized.right))
                        } onReset: {
                            stage.resetWeights()
                        }
                    }
                    entryPane(card)
                        .frame(width: widths[index])
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func entryPane(_ entry: StageEntry) -> some View {
        switch entry {
        case .card(let card):
            pane(card)
        case .inbox:
            WheelhouseInboxView(
                items: inboxItems,
                unavailable: !store.inboxUnavailable.isDisjoint(with: store.wheelhouses.map(\.root)),
                refreshing: store.isRefreshingWork,
                onRefresh: { store.refreshWork() },
                onClose: { stage.remove(WheelhouseStage.inboxEntry) },
                onSeatAction: onSeatAction,
                onRespond: { root, item, response in await store.respond(response, to: item, root: root) })
        }
    }

    private func pane(_ card: TerminalCard) -> some View {
        let found = store.seat(for: card)
        let parent = found == nil ? store.parentSeat(of: card) : nil
        let isFocused = stage.focused == card.id
        let ringing = tabManager.needsAttention.contains(card.id)
        let pinned = stage.isPinned(card.id)
        return VStack(spacing: 0) {
            HStack(spacing: 7) {
                if let parent {
                    quickTerminalHeader(card, seat: parent.seat)
                    if showsWheelhouseNames { wheelhouseLabel(parent.wheelhouse) }
                } else {
                    WheelhouseSeatDot(kind: ringing ? .needsYou : .open)
                    Text(found?.seat.name ?? card.title)
                        .font(.system(size: 12.5, weight: .bold))
                    if let seat = found?.seat {
                        WheelhouseRolePill(seat: seat)
                    }
                    if let found {
                        WheelhouseQuickTerminalBadges(wheelhouse: found.wheelhouse, seat: found.seat)
                    }
                    if showsWheelhouseNames, let wheelhouse = found?.wheelhouse {
                        wheelhouseLabel(wheelhouse)
                    }
                    if let found, let bead = store.currentBead(for: found.seat, in: found.wheelhouse) {
                        Text(bead.title)
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if stage.zoomed == card.id { zoomedNeedsYouBadge }
                if let found {
                    seatActionsMenu(found.wheelhouse, found.seat, card: card)
                } else if parent != nil {
                    paneButton("xmark.octagon", help: Strings.Wheelhouse.closeTerminal) {
                        stage.closeQuickTerminal(card)
                    }
                }
                let zoomed = stage.zoomed == card.id
                paneButton(
                    zoomed ? WheelhouseMenuIcon.exitZoom : WheelhouseMenuIcon.zoom,
                    help: zoomed ? Strings.Wheelhouse.exitZoom : Strings.Wheelhouse.zoomTerminal
                ) {
                    if zoomed { stage.exitZoom() } else { zoom(card) }
                }
                paneButton(
                    pinned ? "pin.fill" : "pin", help: pinned ? Strings.Wheelhouse.unpin : Strings.Wheelhouse.pin
                ) {
                    stage.togglePin(card.id)
                }
                paneButton("xmark", help: Strings.Wheelhouse.smartCloseHelp) {
                    if let found {
                        onSeatAction(found.wheelhouse, found.seat, .closeTerminal)
                    } else if parent != nil {
                        stage.smartClose(card)
                    } else {
                        stage.remove(card.id)
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                ringing
                    ? Color.orange.opacity(0.14)
                    : (isFocused ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .contentShape(Rectangle())
            .onTapGesture { focus(card) }
            .contextMenu { seatCardMenu(card) }
            // Drag a header (or a chip) onto another header to reorder. Only
            // headers take drops: a terminal would paste the payload as text.
            .draggable(WheelhouseStage.dragPayload(card.id)) {
                Text(found?.seat.name ?? card.title)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.3)))
            }
            .dropDestination(for: String.self) { items, _ in
                guard let dragged = items.compactMap(WheelhouseStage.card(fromDragPayload:)).first,
                    dragged != card.id
                else { return false }
                stage.move(dragged, before: card.id)
                if let moved = boardVM.allTerminals.first(where: { $0.id == dragged }) { boardVM.selectCard(moved) }
                return true
            } isTargeted: { over in
                dropTarget = over ? card.id : (dropTarget == card.id ? nil : dropTarget)
            }
            .overlay(alignment: .leading) {
                if dropTarget == card.id {
                    Rectangle().fill(Color.accentColor).frame(width: 3)
                }
            }

            if stage.quickTerminalPlacement == .split, let found {
                WheelhouseSplitSeatBody(seatCard: card, wheelhouse: found.wheelhouse, seat: found.seat) {
                    seatTerminal(card, isFocused: isFocused)
                }
            } else {
                seatTerminal(card, isFocused: isFocused)
            }
        }
        .overlay(
            Rectangle()
                .stroke(
                    ringing ? Color.orange : (isFocused ? Color.accentColor.opacity(0.6) : Color.clear), lineWidth: 1.5)
        )
    }

    private func seatTerminal(_ card: TerminalCard, isFocused: Bool) -> some View {
        TerminalHostView(
            card: card,
            onExit: {},
            onBell: { tabManager.markStageBell(card.id) },
            focusPolicy: .whenBecomingFocused,
            isFocusedPane: isFocused
        )
        .id(card.id)
    }

    private func paneButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .help(help)
    }

    private func seatActionsMenu(_ wheelhouse: Wheelhouse, _ seat: WheelhouseSeat, card: TerminalCard) -> some View {
        Menu {
            Group {
                WheelhouseSeatActionItems(
                    wheelhouse: wheelhouse, seat: seat, hasTerminal: true, onSeatAction: onSeatAction)
                Divider()
                zoomMenuItem(card, showsShortcut: false)
            }
            .labelStyle(.titleAndIcon)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Strings.Wheelhouse.seatActions)
    }

    // MARK: - Actions

    private func show(_ card: TerminalCard) {
        stage.show(card.id)
        boardVM.selectCard(card)
    }

    private func focus(_ card: TerminalCard) {
        stage.focus(card.id)
        boardVM.selectCard(card)
    }

    private func zoom(_ card: TerminalCard) {
        stage.zoom(card.id)
        boardVM.selectCard(card)
    }
}

// MARK: - Split placement

extension WheelhouseStageView {
    /// In Split, the seat card a Quick Terminal sits beneath.
    func splitHostId(of cardId: UUID) -> UUID? {
        guard stage.quickTerminalPlacement == .split,
            let card = boardVM.allTerminals.first(where: { $0.id == cardId })
        else { return nil }
        return store.splitHost(of: card, in: boardVM.allTerminals)?.id
    }

    func moveQuickTerminalsIntoPanels() {
        stage.moveQuickTerminalsIntoPanels { splitHostId(of: $0) }
    }
}

// MARK: - Empty stage

extension WheelhouseStageView {
    var emptyStage: some View {
        VStack(spacing: 10) {
            Image(systemName: "steeringwheel")
                .font(.system(size: 34))
                .foregroundColor(.secondary)
            Text(Strings.Wheelhouse.emptyStageTitle)
                .font(.headline)
            Text(Strings.Wheelhouse.emptyStageMessage)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shortcuts

extension WheelhouseStageView {
    /// Zoom Terminal, or Exit Zoom while this pane is zoomed. Its ⌥⌘Z shows in
    /// the focused pane's right-click menu.
    func zoomMenuItem(_ card: TerminalCard, showsShortcut: Bool? = nil) -> some View {
        let zoomed = stage.zoomed == card.id
        return Button {
            if zoomed { stage.exitZoom() } else { zoom(card) }
        } label: {
            Label(
                zoomed ? Strings.Wheelhouse.exitZoom : Strings.Wheelhouse.zoomTerminal,
                systemImage: zoomed ? WheelhouseMenuIcon.exitZoom : WheelhouseMenuIcon.zoom)
        }
        .stageShortcut((showsShortcut ?? (stage.focused == card.id)) ? WheelhouseStageShortcut.zoom : nil)
    }

    /// While a pane is zoomed, seats that rang still reach the human: a small
    /// badge in its header; clicking it comes back to the stage with the
    /// longest-waiting seat up.
    @ViewBuilder
    var zoomedNeedsYouBadge: some View {
        let waiting = attentionQueue.filter { $0.id != stage.zoomed }
        if let first = waiting.first {
            Button {
                show(first)
            } label: {
                HStack(spacing: 5) {
                    Circle().fill(Color.orange).frame(width: 7, height: 7)
                    Text("\(Strings.Wheelhouse.needsYou) · \(waiting.count)")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(Color.orange.opacity(0.2)))
                .overlay(Capsule().stroke(Color.orange.opacity(0.8), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(chipHelp(first))
        }
    }

    /// The seat of the focused pane: its own, or a Quick Terminal's parent.
    fileprivate var focusedSeat: (wheelhouse: Wheelhouse, seat: WheelhouseSeat)? {
        store.owningSeat(ofCardId: stage.focused, in: stageCards)
    }

    /// ⌘J: the seat that has waited longest comes on stage.
    /// ⌃⌘F: Wheelhouse focus mode on and off.
    /// ⌘I: the focused seat's harness details. ⌘P: keep it on stage, or not.
    var shortcuts: some View {
        ZStack {
            Button("") {
                if let next = attentionQueue.first { show(next) }
            }
            .keyboardShortcut("j", modifiers: .command)
            Button("") { stage.focusMode.toggle() }
                .keyboardShortcut("f", modifiers: [.command, .control])
            Button("") {
                if let found = focusedSeat { onSeatAction(found.wheelhouse, found.seat, .harnessDetails) }
            }
            .keyboardShortcut(WheelhouseStageShortcut.harnessDetails)
            Button("") { stage.togglePinFocused() }
                .keyboardShortcut(WheelhouseStageShortcut.keepOnStage)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}

// MARK: - Inbox chip and Quick Terminal header

extension WheelhouseStageView {
    /// Which Wheelhouse a run of tabs, or a pane, belongs to: shown only when
    /// seats from more than one are open.
    func wheelhouseLabel(_ wheelhouse: Wheelhouse) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "steeringwheel")
                .font(.system(size: 9))
            Text(wheelhouse.title)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(.secondary)
        .help(wheelhouse.root)
    }

    /// Beads waiting on the human: calmer than a seat ringing, since some are
    /// for any human, and only there while there is something in the inbox.
    @ViewBuilder
    private var inboxChip: some View {
        let count = inboxItems.count
        if count > 0 {
            let onStage = stage.isOnStage(WheelhouseStage.inboxEntry)
            Button {
                stage.show(WheelhouseStage.inboxEntry)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "tray.full")
                        .font(.system(size: 11))
                    Text(Strings.Wheelhouse.inboxTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .bold))
                        .padding(.horizontal, 5)
                        .background(Capsule().fill(Color.accentColor.opacity(0.25)))
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(onStage ? 0.22 : 0.1)))
            }
            .buttonStyle(.plain)
            .help(Strings.Wheelhouse.inboxHelp(WheelhouseStore.inboxAssignees().joined(separator: ", ")))
        }
    }

    /// A Quick Terminal's header: its badge, its seat, its number, and
    /// where its shell is.
    @ViewBuilder
    private func quickTerminalHeader(_ card: TerminalCard, seat: WheelhouseSeat) -> some View {
        let number = WheelhouseCardMatcher.quickTerminalNumber(card) ?? 0
        WheelhouseQuickTerminalBadge(
            number: number, running: boardVM.activeSessionCards.contains(card.id), onStage: false)
        Text(seat.name)
            .font(.system(size: 12.5, weight: .bold))
        Text(Strings.Wheelhouse.quickTerminalTitle(number))
            .font(.system(size: 10.5))
            .foregroundColor(.secondary)
        Text(
            (TerminalSessionManager.shared.getCurrentDirectory(for: card.id) ?? card.workingDirectory)
                .replacingOccurrences(of: NSHomeDirectory(), with: "~")
        )
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundColor(.secondary)
        .lineLimit(1)
        .truncationMode(.head)
    }
}

/// Menu items for a seat: its harness focuses, hand off, and birth. Every
/// item has its `WheelhouseMenuIcon`.
struct WheelhouseSeatActionItems: View {
    let wheelhouse: Wheelhouse
    let seat: WheelhouseSeat
    let hasTerminal: Bool
    var unborn: Bool = false
    /// Whether ynh has the seat's harness; nil while unknown.
    var installed: Bool?
    /// Delegates the seat waits on (not committed or missing), named for the
    /// "needs … first" warning.
    var blockedBy: [String] = []
    /// Show the stage's shortcuts beside the items they trigger: only in a
    /// right-click menu on the stage, where they act on the focused seat.
    var showsShortcuts: Bool = false
    let onSeatAction: (Wheelhouse, WheelhouseSeat, WheelhouseSeatAction) -> Void

    /// "Install", or "Install (needs io first)" while its delegates aren't
    /// ready: still clickable, it just says what else is needed.
    private func withNeeds(_ title: String) -> String {
        blockedBy.isEmpty ? title : Strings.Wheelhouse.needsFirst(title, blockedBy.joined(separator: ", "))
    }

    var body: some View {
        if installed == false {
            Button {
                onSeatAction(wheelhouse, seat, .install)
            } label: {
                Label(withNeeds(Strings.Wheelhouse.install), systemImage: WheelhouseMenuIcon.install)
            }
            Divider()
        } else if unborn && !hasTerminal {
            Button {
                onSeatAction(wheelhouse, seat, .birth)
            } label: {
                Label(withNeeds(Strings.Wheelhouse.birth), systemImage: WheelhouseMenuIcon.birth)
            }
            Divider()
        }
        let focuses = wheelhouse.focuses(for: seat)
        if !focuses.isEmpty {
            Section(hasTerminal ? Strings.Wheelhouse.askToFocus : Strings.Wheelhouse.launchWithFocus) {
                ForEach(focuses) { focus in
                    Button {
                        onSeatAction(wheelhouse, seat, .focus(focus))
                    } label: {
                        Label(focus.name.capitalized, systemImage: WheelhouseMenuIcon.focus(named: focus.name))
                    }
                    .help(focus.prompt)
                }
            }
        }
        if hasTerminal {
            Divider()
            Button {
                onSeatAction(wheelhouse, seat, .handoff)
            } label: {
                Label(Strings.Wheelhouse.handoff, systemImage: WheelhouseMenuIcon.handoff)
            }
            Button(role: .destructive) {
                onSeatAction(wheelhouse, seat, .closeTerminal)
            } label: {
                Label(Strings.Wheelhouse.closeTerminal, systemImage: WheelhouseMenuIcon.closeTerminal)
            }
            .help(Strings.Wheelhouse.smartCloseHelp)
            .stageShortcut(showsShortcuts ? WheelhouseStageShortcut.closeTerminal : nil)
        }
        Divider()
        Button {
            onSeatAction(wheelhouse, seat, .quickTerminal)
        } label: {
            Label(Strings.Wheelhouse.newQuickTerminal, systemImage: WheelhouseMenuIcon.quickTerminal)
        }
        .stageShortcut(showsShortcuts ? WheelhouseStageShortcut.quickTerminal : nil)
        Button {
            onSeatAction(wheelhouse, seat, .harnessDetails)
        } label: {
            Label(Strings.Wheelhouse.harnessDetails, systemImage: WheelhouseMenuIcon.harnessDetails)
        }
        .stageShortcut(showsShortcuts ? WheelhouseStageShortcut.harnessDetails : nil)
    }
}
