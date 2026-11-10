import AppKit
import SwiftUI
import TermQShared

/// The Repositories tab's Attention view: every open pull request waiting on
/// the human's review, in any repository, grouped by how long it has waited
/// since the review was asked for, longest first.
struct ReviewActionsView<RowMenu: View>: View {
    let repositoryPaths: [String]
    /// The context menu for a row, built by the sidebar so TermQ's repositories get
    /// the Remote tab's PR menu.
    @ViewBuilder let rowMenu: (ReviewRequest) -> RowMenu
    /// Called with the requests shown, whenever they change, so the sidebar can load
    /// what their menus need and tidy review checkouts.
    var onRequestsChanged: ([ReviewRequest]) async -> Void = { _ in }

    @ObservedObject private var service: ReviewRequestService = .shared
    @ObservedObject private var ghProbe: GhCliProbe = .shared
    @AppStorage("actions.termqRepositoriesOnly") private var termqOnly = false

    private var shown: [ReviewRequest] {
        termqOnly
            ? ReviewRequests.inRepositories(service.requests, names: service.termqRepositories) : service.requests
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Toggle(Strings.Actions.termqOnly, isOn: $termqOnly)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                Spacer()
                if service.isLoading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            Divider()
            content
        }
        .onAppear {
            refresh(force: false)
            service.updateTermQRepositories(paths: repositoryPaths)
        }
        .onChange(of: repositoryPaths) { _, paths in service.updateTermQRepositories(paths: paths) }
        // Waits for the first load, and re-runs (cancelling the last run) when the
        // requests, TermQ's repositories or gh's sign-in change.
        .task(id: service.requests.map(\.id) + service.termqRepositories.sorted() + ["\(ghProbe.status.isReady)"]) {
            guard service.lastLoaded != nil else { return }
            await onRequestsChanged(service.requests)
        }
        // gh may only become ready after the view is up.
        .onChange(of: ghProbe.status) { refresh(force: false) }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { return }
                // Timed refreshes reuse request times; only new ones are asked.
                refresh(force: false, ignoringAge: true)
            }
        }
    }

    private func refresh(force: Bool, ignoringAge: Bool = false) {
        guard case .ready(let ghPath, let login) = ghProbe.status else { return }
        service.refresh(ghPath: ghPath, login: login, force: force, ignoringAge: ignoringAge)
    }

    @ViewBuilder
    private var content: some View {
        switch ghProbe.status {
        case .unauthenticated:
            message(
                Strings.RemotePRs.ghUnauthTitle + "\n" + Strings.RemotePRs.ghUnauthMessage,
                symbol: "person.crop.circle.badge.exclamationmark")
        case .authCheckFailed:
            message(Strings.RemotePRs.ghAuthCheckFailed, symbol: "exclamationmark.triangle")
        case .missing:
            message(Strings.RemotePRs.ghMissingMessage, symbol: "exclamationmark.triangle")
        default:
            requestList
        }
    }

    @ViewBuilder
    private var requestList: some View {
        if let failure = service.failure, !service.requests.isEmpty {
            banner(Strings.Actions.loadFailed(failure))
        }
        if service.truncated {
            banner(Strings.Actions.truncated(ReviewRequests.searchLimit))
        }
        if let failure = service.failure, service.requests.isEmpty {
            message(Strings.Actions.loadFailed(failure), symbol: "exclamationmark.triangle")
        } else if shown.isEmpty && !service.isLoading {
            message(Strings.Actions.empty, symbol: "checkmark.circle")
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                List {
                    ForEach(ReviewRequests.grouped(shown, now: context.date), id: \.wait) { group in
                        Section(Strings.Actions.waitTitle(group.wait)) {
                            ForEach(group.requests) { request in
                                row(request, now: context.date)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private func open(_ request: ReviewRequest) {
        if let url = URL(string: request.url) { NSWorkspace.shared.open(url) }
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.08))
    }

    private func row(_ request: ReviewRequest, now: Date) -> some View {
        Button {
            open(request)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(request.repository)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if request.isDraft {
                        Text(Strings.Actions.draft)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(Color.secondary.opacity(0.18)))
                    }
                    Spacer(minLength: 4)
                    Text(WheelhouseStageView.age(since: request.waitingSince, now: now))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Text("#\(request.number) \(request.title)")
                    .font(.system(size: 12))
                    .lineLimit(2)
                if let author = request.author {
                    Text(author)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(request.url)
        .contextMenu { rowMenu(request) }
    }

    private func message(_ text: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
