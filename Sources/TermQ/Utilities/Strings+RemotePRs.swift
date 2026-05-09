import Foundation

extension Strings {
    enum RemotePRs {
        // MARK: - Sidebar toggle
        static var modeLocal: String { localized("remote.prs.mode.local") }
        static var modeRemote: String { localized("remote.prs.mode.remote") }

        // MARK: - Local mode badges
        static func linkedPR(_ number: Int) -> String {
            String(format: localized("remote.prs.linked.pr %lld"), number)
        }

        // MARK: - Worktree context menu additions
        static var runWithFocus: String { localized("remote.prs.run.with.focus") }
        static var openPROnRemote: String { localized("remote.prs.open.pr.on.remote") }
        static var showInRemote: String { localized("remote.prs.show.in.remote") }
        static var showInLocal: String { localized("remote.prs.show.in.local") }

        // MARK: - Remote mode PR row badges
        static var badgeAuthor: String { localized("remote.prs.badge.author") }
        static var badgeReviewRequested: String { localized("remote.prs.badge.review") }
        static var badgeAssigned: String { localized("remote.prs.badge.assigned") }
        static var badgeDraft: String { localized("remote.prs.badge.draft") }
        static var badgeCheckedOut: String { localized("remote.prs.badge.checked.out") }

        // MARK: - PR row context menus
        static var copyPRURL: String { localized("remote.prs.copy.url") }
        static var checkoutAsWorktree: String { localized("remote.prs.checkout.as.worktree") }
        static var noGitHubRemote: String { localized("remote.prs.no.github.remote") }

        // MARK: - GhCli probe states
        static var ghMissingTitle: String { localized("remote.prs.gh.missing.title") }
        static var ghMissingMessage: String { localized("remote.prs.gh.missing.message") }
        static var ghUnauthTitle: String { localized("remote.prs.gh.unauth.title") }
        static var ghUnauthMessage: String { localized("remote.prs.gh.unauth.message") }
        static var ghAuthCheckFailed: String { localized("remote.prs.gh.auth.failed") }
        static var ghRecheck: String { localized("remote.prs.gh.recheck") }

        // MARK: - Checkout
        static func checkoutToast(_ branch: String) -> String {
            String(format: localized("remote.prs.checkout.toast %@"), branch)
        }
        static var switchToLocal: String { localized("remote.prs.switch.to.local") }
        static var worktreeExists: String { localized("remote.prs.worktree.exists") }
        static var switchToExisting: String { localized("remote.prs.switch.to.existing") }
        static func checkingOut(_ pr: Int) -> String {
            String(format: localized("remote.prs.checking.out %lld"), pr)
        }

        // MARK: - Force-push / Update from Origin
        static var forcePushIndicator: String { localized("remote.prs.force.push.indicator") }
        static var forceUpdateTitle: String { localized("remote.prs.force.update.title") }
        static func forceUpdateMessage(_ modified: Int, _ ahead: Int) -> String {
            String(
                format: localized("remote.prs.force.update.message %lld %lld"),
                modified, ahead
            )
        }
        static var forceUpdateConfirm: String { localized("remote.prs.force.update.confirm") }
        static var forceUpdateCancel: String { localized("remote.prs.force.update.cancel") }

        // MARK: - Run with Focus sheet
        static var runLoadingDetail: String { localized("remote.prs.run.loading.detail") }
        static var runSheetTitle: String { localized("remote.prs.run.sheet.title") }
        static var runHarnessLabel: String { localized("remote.prs.run.harness.label") }
        static var runFocusLabel: String { localized("remote.prs.run.focus.label") }
        static var runFocusNone: String { localized("remote.prs.run.focus.none") }
        static var runProfileLabel: String { localized("remote.prs.run.profile.label") }
        static var runProfileHarnessDefault: String { localized("remote.prs.run.profile.default") }
        static var runPromptLabel: String { localized("remote.prs.run.prompt.label") }
        static var runCustomize: String { localized("remote.prs.run.customize") }
        static var runRun: String { localized("remote.prs.run.run") }
        static var runCancel: String { localized("remote.prs.run.cancel") }

        // MARK: - Prune Closed PRs
        static var pruneClosedPRs: String { localized("remote.prs.prune.closed") }
        static func pruneClosedPRsTitle(_ count: Int) -> String {
            String(format: localized("remote.prs.prune.closed.title %lld"), count)
        }
        static var pruneClosedPRsConfirm: String { localized("remote.prs.prune.closed.confirm") }
        static var pruneClosedPRsNothingTitle: String { localized("remote.prs.prune.closed.nothing.title") }
        static var pruneClosedPRsNothingMessage: String { localized("remote.prs.prune.closed.nothing.message") }
        static var pruneKeep: String { localized("remote.prs.prune.keep") }
        static var pruneRemove: String { localized("remote.prs.prune.remove") }
        static var pruneReasonDirty: String { localized("remote.prs.prune.reason.dirty") }
        static var pruneReasonAhead: String { localized("remote.prs.prune.reason.ahead") }
    }
}
