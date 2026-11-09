import AppKit
import SwiftUI
import TermQCore
import TermQShared

/// Sidebar content for the Wheelhouses tab: every seat of every Wheelhouse,
/// grouped by role group, with a role label on each seat.
///
/// The desk and crew are conversations: clicking one opens it on the stage.
/// Standing roles and workers run unattended, reached through the desk and the
/// dispatcher, so they show as status lines: the bead each one is on.
struct WheelhouseSidebarTab: View {
    @ObservedObject var worktreeViewModel: WorktreeSidebarViewModel
    var onSeatAction: ((Wheelhouse, WheelhouseSeat, WheelhouseSeatAction) -> Void)?

    @ObservedObject private var store: WheelhouseStore = .shared
    @ObservedObject private var stage: WheelhouseStage = .shared
    @ObservedObject private var boardVM: BoardViewModel = .shared
    @ObservedObject private var tabManager: TabManager = BoardViewModel.shared.tabManager
    @ObservedObject private var harnessRepo: HarnessRepository = .shared
    @State private var collapsed: Set<String> = []
    @State private var showingAdd = false

    private var roots: [String] { worktreeViewModel.repositories.map(\.path) }

    private var visibleWheelhouses: [Wheelhouse] {
        guard !stage.selectedRoot.isEmpty else {
            return stage.focusMode ? Array(store.wheelhouses.prefix(1)) : store.wheelhouses
        }
        let match = store.wheelhouses.filter { $0.root == stage.selectedRoot }
        return match.isEmpty ? store.wheelhouses : match
    }

    private var selectedTitle: String {
        if let match = store.wheelhouses.first(where: { $0.root == stage.selectedRoot }) { return match.title }
        if stage.focusMode, let first = store.wheelhouses.first { return first.title }
        return Strings.Wheelhouse.allWheelhouses
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.wheelhouses.isEmpty && !store.isLoading {
                emptyState
            } else {
                list
            }
        }
        .onAppear {
            store.refresh(roots: roots)
            // Seat health needs to know which harnesses ynh has.
            if !harnessRepo.listState.isLoaded, case .ready = YNHDetector.shared.status {
                Task { await harnessRepo.refresh() }
            }
        }
        .onChange(of: roots) { _, newRoots in store.refresh(roots: newRoots) }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            store.refresh(roots: roots)
        }
        // An install or uninstall changes what a seat needs.
        .onChange(of: harnessRepo.harnesses.map(\.name)) { store.refreshDelegateIssues() }
        .sheet(isPresented: $showingAdd) {
            WheelhouseAddSheet { root in await addWheelhouse(root: root) }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: WheelhouseStore.workRefreshInterval)
                guard !Task.isCancelled else { return }
                store.refreshWork()
                // Commits made in a terminal show up without leaving the app.
                store.refreshDelegateIssues()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Menu {
                Group {
                    if !stage.focusMode {
                        Button {
                            stage.selectedRoot = ""
                        } label: {
                            Label(Strings.Wheelhouse.allWheelhouses, systemImage: WheelhouseMenuIcon.allWheelhouses)
                        }
                        if !store.wheelhouses.isEmpty { Divider() }
                    }
                    ForEach(store.wheelhouses) { wheelhouse in
                        Button {
                            stage.selectedRoot = wheelhouse.root
                        } label: {
                            Label(wheelhouse.title, systemImage: WheelhouseMenuIcon.wheelhouse)
                        }
                    }
                    Divider()
                    Button {
                        showingAdd = true
                    } label: {
                        Label(Strings.Wheelhouse.addWheelhouse, systemImage: WheelhouseMenuIcon.add)
                    }
                }
                .labelStyle(.titleAndIcon)
            } label: {
                Text(selectedTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            if store.isLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                showingAdd = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help(Strings.Wheelhouse.addWheelhouse)
            Button {
                store.refresh(roots: roots)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help(Strings.Wheelhouse.refreshHelp)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Adding a Wheelhouse

    /// Checks `root` holds a roster and registers it as a repository, which
    /// is where TermQ looks for Wheelhouses. Nil on success, else why not.
    private func addWheelhouse(root: String) async -> String? {
        guard WheelhouseLoader.isWheelhouse(root: root) else {
            return Strings.Wheelhouse.notAWheelhouse(URL(fileURLWithPath: root).lastPathComponent)
        }
        stage.selectedRoot = root
        guard !roots.contains(where: { URL(fileURLWithPath: $0).standardizedFileURL.path == root }) else {
            store.refresh(roots: roots)
            return nil
        }
        do {
            try await worktreeViewModel.addRepository(path: root)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "steeringwheel")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text(Strings.Wheelhouse.emptyTitle)
                .font(.headline)
            Text(Strings.Wheelhouse.emptyMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(Strings.Wheelhouse.addWheelhouse) { showingAdd = true }
                .controlSize(.small)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visibleWheelhouses) { wheelhouse in
                    wheelhouseSection(wheelhouse)
                }
                ForEach(store.failures, id: \.root) { failure in
                    Label(
                        Strings.Wheelhouse.loadFailed(URL(fileURLWithPath: failure.root).lastPathComponent),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundColor(.orange)
                    .help(failure.reason)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func wheelhouseSection(_ wheelhouse: Wheelhouse) -> some View {
        let isCollapsed = collapsed.contains(wheelhouse.root)
        let waiting = attentionCount(in: wheelhouse)
        Button {
            if isCollapsed { collapsed.remove(wheelhouse.root) } else { collapsed.insert(wheelhouse.root) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 10)
                Image(systemName: "steeringwheel")
                    .foregroundColor(.accentColor)
                Text(wheelhouse.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(Strings.Wheelhouse.seatCount(wheelhouse.seats.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if waiting > 0 {
                    Text("\(waiting)")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 5)
                        .background(Capsule().fill(Color.orange))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(wheelhouse.root)

        if !isCollapsed {
            if store.workUnavailable.contains(wheelhouse.root) {
                Text(Strings.Wheelhouse.workUnavailable)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, 28)
                    .padding(.bottom, 2)
            }
            ForEach(wheelhouse.seatsByGroup, id: \.group) { entry in
                groupHeader(entry.group)
                ForEach(entry.seats) { seat in
                    if entry.group.isConversational {
                        conversationRow(seat, in: wheelhouse)
                    } else {
                        statusRow(seat, in: wheelhouse)
                    }
                }
            }
        }
    }

    private func groupHeader(_ group: WheelhouseGroup) -> some View {
        HStack(spacing: 4) {
            Text(Strings.Wheelhouse.groupLabel(group).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            if let hint = Strings.Wheelhouse.groupHint(group) {
                Text("· \(hint)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .padding(.leading, 28)
        .padding(.trailing, 10)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    // MARK: - Seat state

    private func seatCard(_ seat: WheelhouseSeat, in wheelhouse: Wheelhouse) -> TerminalCard? {
        WheelhouseCardMatcher.card(
            in: boardVM.allTerminals, wheelhouseRoot: wheelhouse.root, seatCommand: seat.command)
    }

    /// What stops the seat from running, if anything. A seat's command is its
    /// ynh harness name, so that is what "installed" looks for.
    private func seatIssues(_ seat: WheelhouseSeat, in wheelhouse: Wheelhouse) -> [WheelhouseSeatIssue] {
        store.issues(for: seat, in: wheelhouse, installed: harnessRepo.isInstalled(name: seat.command))
    }

    private func needsYou(_ card: TerminalCard?) -> Bool {
        guard let card else { return false }
        return tabManager.needsAttention.contains(card.id)
    }

    /// The dot means the same for every seat: orange when it needs you,
    /// filled when its terminal's session is running, green when it has no
    /// running terminal but checked in on a bead recently (a dispatcher may
    /// be running it), hollow otherwise.
    private func dotKind(
        _ card: TerminalCard?, seat: WheelhouseSeat, in wheelhouse: Wheelhouse
    ) -> WheelhouseSeatDot.Kind {
        if let card, needsYou(card) { return .needsYou }
        if let card, boardVM.activeSessionCards.contains(card.id) { return .open }
        return store.isWorking(seat, in: wheelhouse) ? .working : .closed
    }

    private func attentionCount(in wheelhouse: Wheelhouse) -> Int {
        wheelhouse.seats.filter { needsYou(seatCard($0, in: wheelhouse)) }.count
    }

    // MARK: - Conversation rows (desk, crew)

    private func conversationRow(_ seat: WheelhouseSeat, in wheelhouse: Wheelhouse) -> some View {
        let card = seatCard(seat, in: wheelhouse)
        let dot = dotKind(card, seat: seat, in: wheelhouse)
        let onStage = card.map { stage.isOnStage($0.id) } ?? false
        let bead = store.currentBead(for: seat, in: wheelhouse)
        return Button {
            onSeatAction?(wheelhouse, seat, .open)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    WheelhouseSeatDot(kind: dot)
                    Text(seat.name)
                        .font(.system(size: 13, weight: onStage ? .semibold : .regular))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if store.isUnborn(seat, in: wheelhouse) && card == nil {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                            .foregroundColor(.yellow)
                            .help(Strings.Wheelhouse.unbornHelp)
                    }
                    if let card, stage.isPinned(card.id) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.accentColor)
                    }
                    WheelhouseQuickTerminalBadges(wheelhouse: wheelhouse, seat: seat)
                    Spacer(minLength: 4)
                    WheelhouseRolePill(seat: seat)
                }
                // Same line as every other seat: its bead, or idle.
                statusLine(bead: bead, extra: max(0, store.beadCount(for: seat, in: wheelhouse) - 1))
                    .padding(.leading, 16)
            }
            .padding(.leading, 28)
            .padding(.trailing, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(onStage ? Color.accentColor.opacity(0.16) : Color.clear)
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(seat.mandate ?? seat.name)
        .contextMenu { seatMenu(seat, in: wheelhouse, card: card) }
    }

    // MARK: - Status rows (standing, workers)

    private func statusRow(_ seat: WheelhouseSeat, in wheelhouse: Wheelhouse) -> some View {
        let card = seatCard(seat, in: wheelhouse)
        let bead = store.currentBead(for: seat, in: wheelhouse)
        let extra = max(0, store.beadCount(for: seat, in: wheelhouse) - 1)
        // The dot means the same everywhere: does this seat have a terminal?
        // What it is working on is the line underneath.
        let dot = dotKind(card, seat: seat, in: wheelhouse)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                WheelhouseSeatDot(kind: dot)
                Text(seat.name)
                    .font(.system(size: 12))
                    .foregroundColor(bead == nil ? .secondary : .primary)
                    .lineLimit(1)
                WheelhouseQuickTerminalBadges(wheelhouse: wheelhouse, seat: seat)
                Spacer(minLength: 4)
                WheelhouseRolePill(seat: seat)
            }
            statusLine(bead: bead, extra: extra)
                .padding(.leading, 16)
        }
        .padding(.leading, 28)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            // One rule for every seat: a click opens it.
            onSeatAction?(wheelhouse, seat, .open)
        }
        .help(seat.mandate ?? seat.name)
        .contextMenu { seatMenu(seat, in: wheelhouse, card: card) }
    }

    @ViewBuilder
    private func statusLine(bead: WheelhouseBead?, extra: Int) -> some View {
        if let bead {
            // One line that truncates as a whole, so a narrow sidebar never
            // splits the bead id across lines.
            (Text(bead.id).font(.system(size: 10, design: .monospaced))
                + Text(" " + bead.title).font(.system(size: 10.5))
                + Text(extra > 0 ? "  +\(extra)" : "").font(.system(size: 10)))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            if let pr = bead.pullRequestShortName {
                Text(Strings.Wheelhouse.waitingOn(pr))
                    .font(.system(size: 10))
                    .foregroundColor(.purple)
            }
        } else {
            Text(Strings.Wheelhouse.statusIdle)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary.opacity(0.7))
        }
    }

    private func seatMenu(_ seat: WheelhouseSeat, in wheelhouse: Wheelhouse, card: TerminalCard?) -> some View {
        seatMenuItems(seat, in: wheelhouse, card: card).labelStyle(.titleAndIcon)
    }

    @ViewBuilder
    private func seatMenuItems(_ seat: WheelhouseSeat, in wheelhouse: Wheelhouse, card: TerminalCard?) -> some View {
        // Same shape for every seat: open first, then the seat's own actions.
        Button {
            onSeatAction?(wheelhouse, seat, .open)
        } label: {
            if card == nil {
                Label(Strings.Wheelhouse.openTerminal, systemImage: WheelhouseMenuIcon.openTerminal)
            } else {
                Label(Strings.Wheelhouse.showTerminal, systemImage: WheelhouseMenuIcon.showTerminal)
            }
        }
        Divider()
        if let onSeatAction {
            let issues = seatIssues(seat, in: wheelhouse)
            WheelhouseSeatActionItems(
                wheelhouse: wheelhouse, seat: seat, hasTerminal: card != nil,
                unborn: store.isUnborn(seat, in: wheelhouse), installed: harnessRepo.isInstalled(name: seat.command),
                blockedBy: WheelhouseSeatHealth.blockingDelegates(in: issues), onSeatAction: onSeatAction)
            Divider()
        }
        if let card {
            WheelhouseKeepOnStageToggle(cardId: card.id)
        }
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(seat.command, forType: .string)
        } label: {
            Label(Strings.Wheelhouse.copyCommand, systemImage: WheelhouseMenuIcon.copy)
        }
        if let harness = seat.harness {
            Button {
                let url = URL(fileURLWithPath: wheelhouse.root).appendingPathComponent(harness)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label(Strings.Wheelhouse.revealInFinder, systemImage: WheelhouseMenuIcon.revealInFinder)
            }
        }
    }
}

// MARK: - Shared pieces

/// A seat's status dot.
struct WheelhouseSeatDot: View {
    enum Kind {
        /// Rang the bell: the human is next.
        case needsYou
        /// Its terminal's session is running.
        case open
        /// No running terminal of its own, but it checked in on a bead recently.
        case working
        /// No running session.
        case closed
    }

    let kind: Kind

    var body: some View {
        switch kind {
        case .needsYou:
            Circle()
                .fill(Color.orange)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.orange.opacity(0.35), lineWidth: 3))
        case .open:
            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)
        case .working:
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .help(Strings.Wheelhouse.workingHelp)
        case .closed:
            Circle()
                .stroke(Color.secondary.opacity(0.7), lineWidth: 1.5)
                .frame(width: 8, height: 8)
        }
    }
}

/// One numbered badge per Quick Terminal a seat has, in the sidebar and in
/// the seat's pane header: click one to show it where Quick Terminals go (its
/// own place on stage, or the panel beneath its seat), right-click to close it.
struct WheelhouseQuickTerminalBadges: View {
    let wheelhouse: Wheelhouse
    let seat: WheelhouseSeat

    @ObservedObject private var stage: WheelhouseStage = .shared
    @ObservedObject private var boardVM: BoardViewModel = .shared

    var body: some View {
        let terminals = WheelhouseCardMatcher.quickTerminals(
            in: boardVM.allTerminals, wheelhouseRoot: wheelhouse.root, seatCommand: seat.command)
        let seatCard = WheelhouseCardMatcher.card(
            in: boardVM.allTerminals, wheelhouseRoot: wheelhouse.root, seatCommand: seat.command)
        // In Split, the one a seat's panel shows counts as on stage.
        let shownInPanel =
            stage.quickTerminalPlacement == .split
            ? seatCard.flatMap { seatCard in
                stage.isOnStage(seatCard.id)
                    ? stage.splitQuickTerminal(for: seatCard.id, among: terminals.map(\.id)) : nil
            } : nil
        HStack(spacing: 3) {
            ForEach(terminals, id: \.id) { card in
                let number = WheelhouseCardMatcher.quickTerminalNumber(card) ?? 0
                WheelhouseQuickTerminalBadge(
                    number: number, running: boardVM.activeSessionCards.contains(card.id),
                    onStage: stage.isOnStage(card.id) || shownInPanel == card.id
                )
                .help(Strings.Wheelhouse.quickTerminalHelp(number, seat.name))
                .highPriorityGesture(
                    TapGesture().onEnded {
                        stage.showQuickTerminal(card.id, seatCard: seatCard?.id)
                        if stage.quickTerminalPlacement == .split, let seatCard {
                            boardVM.selectCard(seatCard)
                        } else {
                            boardVM.selectCard(card)
                        }
                    }
                )
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
    }
}

/// A seat's Quick Terminal: its number in a small accent circle, solid
/// while its shell runs, outlined once it has ended, ringed while on stage.
struct WheelhouseQuickTerminalBadge: View {
    let number: Int
    let running: Bool
    let onStage: Bool

    var body: some View {
        Text("\(number)")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundColor(running ? .white : .accentColor)
            .frame(width: 15, height: 15)
            .background(Circle().fill(running ? Color.accentColor : Color.clear))
            .overlay(Circle().stroke(Color.accentColor, lineWidth: running ? 0 : 1))
            .overlay(Circle().stroke(Color.accentColor.opacity(onStage ? 0.45 : 0), lineWidth: 2).padding(-2.5))
            .contentShape(Circle())
    }
}

/// A seat's role: symbol plus label, such as "Builder · ynh".
struct WheelhouseRolePill: View {
    let seat: WheelhouseSeat

    var body: some View {
        if let role = seat.effectiveRole, let label = Strings.Wheelhouse.roleLabel(for: seat) {
            HStack(spacing: 3) {
                Image(systemName: role.symbolName)
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 10.5))
                    .lineLimit(1)
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)))
        }
    }
}

/// Settings' Wheelhouses section. More Wheelhouse settings go here.
struct WheelhouseSettingsSection: View {
    @ObservedObject private var stage: WheelhouseStage = .shared

    var body: some View {
        Section {
            WheelhouseTabSettingToggle()
            Picker(Strings.Settings.Wheelhouse.quickTerminalPlacement, selection: $stage.quickTerminalPlacement) {
                Text(Strings.Settings.Wheelhouse.placementStaged).tag(WheelhouseQuickTerminalPlacement.staged)
                Text(Strings.Settings.Wheelhouse.placementSplit).tag(WheelhouseQuickTerminalPlacement.split)
            }
            .help(Strings.Settings.Wheelhouse.quickTerminalPlacementHelp)
        } header: {
            Text(Strings.Wheelhouse.title)
        }
    }
}

/// Settings toggle for the Wheelhouses sidebar tab (`feature.wheelhouseTab`),
/// and, while it is on, the names whose beads make up the human's inbox.
struct WheelhouseTabSettingToggle: View {
    @AppStorage("feature.wheelhouseTab") private var enabled = false
    @AppStorage(WheelhouseStore.inboxHumanNameKey) private var humanName = WheelhouseInbox.defaultHumanName
    @AppStorage(WheelhouseStore.inboxOwnNameKey) private var ownName = ""

    var body: some View {
        Toggle(Strings.Settings.Wheelhouse.enableTab, isOn: $enabled)
            .help(Strings.Settings.Wheelhouse.enableTabHelp)
        if enabled {
            TextField(
                Strings.Settings.Wheelhouse.inboxHumanName, text: $humanName,
                prompt: Text(WheelhouseInbox.defaultHumanName)
            )
            .help(Strings.Settings.Wheelhouse.inboxHumanNameHelp)
            .onSubmit { WheelhouseStore.shared.refreshWork() }
            TextField(Strings.Settings.Wheelhouse.inboxOwnName, text: $ownName)
                .help(Strings.Settings.Wheelhouse.inboxOwnNameHelp)
                .onSubmit { WheelhouseStore.shared.refreshWork() }
        }
    }
}
