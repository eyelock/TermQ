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
    @AppStorage("wheelhouse.selected") private var selectedRoot: String = ""
    @State private var collapsed: Set<String> = []
    @State private var addError: String?

    private var roots: [String] { worktreeViewModel.repositories.map(\.path) }

    private var visibleWheelhouses: [Wheelhouse] {
        guard !selectedRoot.isEmpty else {
            return stage.focusMode ? Array(store.wheelhouses.prefix(1)) : store.wheelhouses
        }
        let match = store.wheelhouses.filter { $0.root == selectedRoot }
        return match.isEmpty ? store.wheelhouses : match
    }

    private var selectedTitle: String {
        if let match = store.wheelhouses.first(where: { $0.root == selectedRoot }) { return match.title }
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
        .onAppear { store.refresh(roots: roots) }
        .onChange(of: roots) { _, newRoots in store.refresh(roots: newRoots) }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            store.refresh(roots: roots)
        }
        .alert(
            Strings.Wheelhouse.addFailedTitle,
            isPresented: Binding(get: { addError != nil }, set: { if !$0 { addError = nil } })
        ) {
            Button(Strings.Common.ok) { addError = nil }
        } message: {
            Text(addError ?? "")
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: WheelhouseStore.workRefreshInterval)
                guard !Task.isCancelled else { return }
                store.refreshWork()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Menu {
                if !stage.focusMode {
                    Button(Strings.Wheelhouse.allWheelhouses) { selectedRoot = "" }
                    if !store.wheelhouses.isEmpty { Divider() }
                }
                ForEach(store.wheelhouses) { wheelhouse in
                    Button(wheelhouse.title) { selectedRoot = wheelhouse.root }
                }
                Divider()
                Button(Strings.Wheelhouse.addWheelhouse) { chooseWheelhouseFolder() }
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
                chooseWheelhouseFolder()
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

    /// Picks a folder, checks it holds a roster, and registers it as a
    /// repository, which is where TermQ looks for Wheelhouses.
    private func chooseWheelhouseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = Strings.Wheelhouse.addWheelhouse
        panel.message = Strings.Wheelhouse.addPanelMessage
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.standardizedFileURL.path
        guard WheelhouseLoader.isWheelhouse(root: path) else {
            addError = Strings.Wheelhouse.notAWheelhouse(url.lastPathComponent)
            return
        }
        selectedRoot = path
        guard !roots.contains(where: { URL(fileURLWithPath: $0).standardizedFileURL.path == path }) else {
            store.refresh(roots: roots)
            return
        }
        Task {
            do {
                try await worktreeViewModel.addRepository(path: path)
            } catch {
                addError = error.localizedDescription
            }
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
            Button(Strings.Wheelhouse.addWheelhouse) { chooseWheelhouseFolder() }
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

    private func needsYou(_ card: TerminalCard?) -> Bool {
        guard let card else { return false }
        return tabManager.needsAttention.contains(card.id)
    }

    /// The dot means the same for every seat: orange when it needs you,
    /// filled when its terminal's session is running, hollow otherwise (no
    /// terminal, or one whose session isn't running yet).
    private func dotKind(_ card: TerminalCard?) -> WheelhouseSeatDot.Kind {
        guard let card else { return .closed }
        if needsYou(card) { return .needsYou }
        return boardVM.activeSessionCards.contains(card.id) ? .open : .closed
    }

    private func attentionCount(in wheelhouse: Wheelhouse) -> Int {
        wheelhouse.seats.filter { needsYou(seatCard($0, in: wheelhouse)) }.count
    }

    // MARK: - Conversation rows (desk, crew)

    private func conversationRow(_ seat: WheelhouseSeat, in wheelhouse: Wheelhouse) -> some View {
        let card = seatCard(seat, in: wheelhouse)
        let dot = dotKind(card)
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
        let dot = dotKind(card)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                WheelhouseSeatDot(kind: dot)
                Text(seat.name)
                    .font(.system(size: 12))
                    .foregroundColor(bead == nil ? .secondary : .primary)
                    .lineLimit(1)
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

    @ViewBuilder
    private func seatMenu(_ seat: WheelhouseSeat, in wheelhouse: Wheelhouse, card: TerminalCard?) -> some View {
        // Same shape for every seat: open first, then the seat's own actions.
        Button(card == nil ? Strings.Wheelhouse.openTerminal : Strings.Wheelhouse.showTerminal) {
            onSeatAction?(wheelhouse, seat, .open)
        }
        Divider()
        if let onSeatAction {
            WheelhouseSeatActionItems(
                wheelhouse: wheelhouse, seat: seat, hasTerminal: card != nil,
                unborn: store.isUnborn(seat, in: wheelhouse), onSeatAction: onSeatAction)
            Divider()
        }
        if let card {
            WheelhouseKeepOnStageToggle(cardId: card.id)
        }
        Button(Strings.Wheelhouse.copyCommand) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(seat.command, forType: .string)
        }
        if let harness = seat.harness {
            Button(Strings.Wheelhouse.revealInFinder) {
                let url = URL(fileURLWithPath: wheelhouse.root).appendingPathComponent(harness)
                NSWorkspace.shared.activateFileViewerSelecting([url])
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
        case .closed:
            Circle()
                .stroke(Color.secondary.opacity(0.7), lineWidth: 1.5)
                .frame(width: 8, height: 8)
        }
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

/// Settings toggle for the Wheelhouses sidebar tab (`feature.wheelhouseTab`).
struct WheelhouseTabSettingToggle: View {
    @AppStorage("feature.wheelhouseTab") private var enabled = false

    var body: some View {
        Toggle(Strings.Settings.Wheelhouse.enableTab, isOn: $enabled)
            .help(Strings.Settings.Wheelhouse.enableTabHelp)
    }
}
