import AppKit
import SwiftUI
import TermQShared

/// The human's inbox on the stage: beads that are ready and assigned to a
/// name the human answers to. Read-only on the work graph: a bead can be
/// opened, copied, or handed to a seat, whose session then acts on it.
struct WheelhouseInboxView: View {
    let items: [(wheelhouse: Wheelhouse, item: WheelhouseInboxItem)]
    let unavailable: Bool
    let refreshing: Bool
    let onRefresh: () -> Void
    let onClose: () -> Void
    let onSeatAction: (Wheelhouse, WheelhouseSeat, WheelhouseSeatAction) -> Void
    /// Comments on or closes a bead in a Wheelhouse root; nil on success,
    /// else what went wrong.
    let onRespond: (String, WheelhouseInboxItem, WheelhouseInbox.Response) async -> String?

    @State private var expanded: Set<String> = []
    @State private var responding: InboxResponseRequest?
    /// The one kind shown, such as `decision`; nil for every kind.
    @State private var kindFilter: String?
    /// The seat each bead was last sent to from here, by bead id.
    @State private var sentTo: [String: String] = [:]
    /// Wheelhouse roots whose beads are folded away to their heading.
    @State private var collapsed: Set<String> = []

    /// Each kind in the inbox with how many beads have it, most first.
    private var kinds: [(kind: String, count: Int)] {
        let counts = Dictionary(grouping: items.compactMap(\.item.kind), by: { $0 }).mapValues(\.count)
        return counts.map { (kind: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.kind < $1.kind }
    }

    private var visibleItems: [(wheelhouse: Wheelhouse, item: WheelhouseInboxItem)] {
        guard let kindFilter else { return items }
        return items.filter { $0.item.kind == kindFilter }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if kinds.count > 1 {
                filterBar
                Divider()
            }
            if items.isEmpty {
                Text(unavailable ? Strings.Wheelhouse.inboxUnavailable : Strings.Wheelhouse.inboxEmpty)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let shown = visibleItems
                        let grouped = Set(shown.map(\.wheelhouse.root)).count > 1
                        ForEach(Array(shown.enumerated()), id: \.element.item.id) { index, entry in
                            if grouped && (index == 0 || shown[index - 1].wheelhouse.root != entry.wheelhouse.root) {
                                sectionHeader(entry.wheelhouse)
                            }
                            if !grouped || !collapsed.contains(entry.wheelhouse.root) {
                                row(entry.item, in: entry.wheelhouse)
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(item: $responding) { request in
            WheelhouseInboxResponseSheet(request: request, onRespond: onRespond)
        }
        .onChange(of: kinds.map(\.kind)) { _, kinds in
            if let kindFilter, !kinds.contains(kindFilter) { self.kindFilter = nil }
        }
    }

    /// Filters the inbox to one kind of bead.
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                filterChip(Strings.Wheelhouse.inboxFilterAll, count: items.count, selected: kindFilter == nil) {
                    kindFilter = nil
                }
                ForEach(kinds, id: \.kind) { entry in
                    filterChip(entry.kind, count: entry.count, selected: kindFilter == entry.kind) {
                        kindFilter = kindFilter == entry.kind ? nil : entry.kind
                    }
                    .help(Strings.Wheelhouse.inboxFilterHelp(entry.kind))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
    }

    private func filterChip(_ label: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                Text("\(count)").foregroundColor(selected ? .accentColor : .secondary)
            }
            .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(selected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "tray.full")
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
            Text(Strings.Wheelhouse.inboxTitle)
                .font(.system(size: 12.5, weight: .bold))
            Text("\(items.count)")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(.accentColor)
                .padding(.horizontal, 5)
                .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            Text(WheelhouseStore.inboxAssignees().joined(separator: ", "))
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if refreshing {
                ProgressView().controlSize(.mini).frame(width: 20, height: 20)
            } else {
                headerButton("arrow.clockwise", help: Strings.Wheelhouse.inboxRefreshHelp, action: onRefresh)
            }
            headerButton("xmark", help: Strings.Wheelhouse.takeOffStage, action: onClose)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Color.primary.opacity(0.04))
    }

    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .help(help)
    }

    // MARK: - Rows

    /// Starts each Wheelhouse's beads when the inbox holds more than one's.
    private func sectionHeader(_ wheelhouse: Wheelhouse) -> some View {
        let count = visibleItems.filter { $0.wheelhouse.root == wheelhouse.root }.count
        let isCollapsed = collapsed.contains(wheelhouse.root)
        return HStack(spacing: 5) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 10)
            Image(systemName: "steeringwheel")
                .font(.system(size: 10))
            Text(wheelhouse.title)
                .font(.system(size: 11, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold))
            Spacer()
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.06))
        .contentShape(Rectangle())
        .onTapGesture {
            if isCollapsed { collapsed.remove(wheelhouse.root) } else { collapsed.insert(wheelhouse.root) }
        }
        .help(wheelhouse.root)
    }

    private func row(_ item: WheelhouseInboxItem, in wheelhouse: Wheelhouse) -> some View {
        let isExpanded = expanded.contains(item.id)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("P\(item.priority)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(item.priority <= 1 ? .accentColor : .secondary)
                Text(item.id)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                if let kind = item.kind {
                    Button {
                        kindFilter = kindFilter == kind ? nil : kind
                    } label: {
                        Text(kind)
                            .font(.system(size: 10))
                            .foregroundColor(kindFilter == kind ? .accentColor : .secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                    .help(Strings.Wheelhouse.inboxFilterHelp(kind))
                }
                Spacer(minLength: 4)
                actions(item, in: wheelhouse)
            }
            WheelhouseLinkText(text: item.title, fontSize: 12.5, lineLimit: isExpanded ? nil : 2)
            HStack(spacing: 8) {
                Text(meta(item))
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                sentLabel(item)
            }
            if item.details != nil || item.notes != nil {
                Button(isExpanded ? Strings.Wheelhouse.inboxHideDetails : Strings.Wheelhouse.inboxShowDetails) {
                    if isExpanded { expanded.remove(item.id) } else { expanded.insert(item.id) }
                }
                .buttonStyle(.link)
                .font(.system(size: 10.5))
                if isExpanded {
                    ForEach([item.details, item.notes].compactMap { $0 }, id: \.self) { text in
                        WheelhouseLinkText(text: text, fontSize: 11, secondary: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .contextMenu { rowMenu(item, in: wheelhouse).labelStyle(.titleAndIcon) }
    }

    /// "for stakker · from ynw · unblocks 1".
    private func meta(_ item: WheelhouseInboxItem) -> String {
        var parts = [Strings.Wheelhouse.inboxFor(item.assignee)]
        if let askedBy = item.askedBy { parts.append(Strings.Wheelhouse.inboxFrom(askedBy)) }
        if item.unblocks > 0 { parts.append(Strings.Wheelhouse.inboxUnblocks(item.unblocks)) }
        return parts.joined(separator: " · ")
    }

    /// "sent to Eno", once the bead was handed to a seat from here.
    @ViewBuilder
    private func sentLabel(_ item: WheelhouseInboxItem) -> some View {
        if let seat = sentTo[item.id] {
            Label(Strings.Wheelhouse.inboxSentTo(seat), systemImage: "paperplane")
                .font(.system(size: 10.5))
                .foregroundColor(.accentColor)
        }
    }

    @ViewBuilder
    private func actions(_ item: WheelhouseInboxItem, in wheelhouse: Wheelhouse) -> some View {
        if let ref = item.externalRef, let url = URL(string: ref) {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label(
                    item.externalRefShortName ?? Strings.Wheelhouse.inboxOpenLink,
                    systemImage: WheelhouseMenuIcon.openLink
                )
                .font(.system(size: 10.5))
            }
            .buttonStyle(.borderless)
            .help(ref)
        }
        Menu {
            rowMenu(item, in: wheelhouse).labelStyle(.titleAndIcon)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// What can be done with a bead: the same on its ⋯ button and on a
    /// right-click anywhere on its row.
    @ViewBuilder
    private func rowMenu(_ item: WheelhouseInboxItem, in wheelhouse: Wheelhouse) -> some View {
        Section(Strings.Wheelhouse.inboxSendTo) {
            ForEach(wheelhouse.seats.filter { $0.group.isConversational }) { seat in
                Button {
                    onSeatAction(wheelhouse, seat, .send(Strings.Wheelhouse.inboxSendPrompt(item.id, item.title)))
                    sentTo[item.id] = seat.name
                } label: {
                    Label(seat.name, systemImage: WheelhouseMenuIcon.sendToSeat)
                }
            }
        }
        Divider()
        Button {
            responding = InboxResponseRequest(root: wheelhouse.root, item: item, closing: false)
        } label: {
            Label(Strings.Wheelhouse.inboxComment, systemImage: WheelhouseMenuIcon.comment)
        }
        Button {
            responding = InboxResponseRequest(root: wheelhouse.root, item: item, closing: true)
        } label: {
            Label(Strings.Wheelhouse.inboxClose, systemImage: WheelhouseMenuIcon.closeBead)
        }
        Divider()
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.id, forType: .string)
        } label: {
            Label(Strings.Wheelhouse.inboxCopyId, systemImage: WheelhouseMenuIcon.copy)
        }
        if let ref = item.externalRef {
            Button {
                if let url = URL(string: ref) { NSWorkspace.shared.open(url) }
            } label: {
                Label(Strings.Wheelhouse.inboxOpenLink, systemImage: WheelhouseMenuIcon.openLink)
            }
        }
    }
}

// MARK: - Comment or close

struct InboxResponseRequest: Identifiable {
    let root: String
    let item: WheelhouseInboxItem
    /// Closing the bead, rather than only commenting on it.
    let closing: Bool
    var id: String { item.id }
}

/// Asks for a comment, or a reason for closing, and runs it with `bd`.
struct WheelhouseInboxResponseSheet: View {
    let request: InboxResponseRequest
    let onRespond: (String, WheelhouseInboxItem, WheelhouseInbox.Response) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var running = false
    @State private var failure: String?

    private var canSubmit: Bool {
        !running && (request.closing || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(request.closing ? Strings.Wheelhouse.inboxCloseButton : Strings.Wheelhouse.inboxCommentButton)
                .font(.headline)
            HStack(spacing: 6) {
                Text(request.item.id)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Text(request.item.title)
                    .font(.system(size: 12))
                    .lineLimit(2)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(size: 12.5))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                if text.isEmpty {
                    Text(
                        request.closing
                            ? Strings.Wheelhouse.inboxClosePlaceholder : Strings.Wheelhouse.inboxCommentPlaceholder
                    )
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .allowsHitTesting(false)
                }
            }
            .frame(minHeight: request.closing ? 70 : 140)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
            if let failure {
                Text(Strings.Wheelhouse.inboxRespondFailed + ": " + failure)
                    .font(.caption)
                    .foregroundColor(.red)
                    .textSelection(.enabled)
            }
            HStack {
                if running { ProgressView().controlSize(.small) }
                Spacer()
                Button(Strings.Common.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(request.closing ? Strings.Wheelhouse.inboxCloseButton : Strings.Wheelhouse.inboxCommentButton) {
                    submit()
                }
                // Return makes a new line in the editor; Command-Return sends.
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            }
        }
        .padding(16)
        .frame(width: 520)
    }

    private func submit() {
        let response: WheelhouseInbox.Response = request.closing ? .close(reason: text) : .comment(text)
        running = true
        failure = nil
        Task {
            let result = await onRespond(request.root, request.item, response)
            running = false
            if let result { failure = result } else { dismiss() }
        }
    }
}
