import Foundation
import TermQShared

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
        static var removeReviewCheckout: String { localized("remote.prs.remove.review.checkout") }
        static var removeReviewCheckoutTitle: String { localized("remote.prs.remove.review.checkout.title") }
        static var removeReviewCheckoutDirty: String { localized("remote.prs.remove.review.checkout.dirty") }
        static func carryFailed(_ folder: String, _ reason: String) -> String {
            String(format: localized("remote.prs.carry.failed %@ %@"), folder, reason)
        }
        static func reviewKeptChanged(_ folder: String) -> String {
            String(format: localized("remote.prs.review.kept.changed %@"), folder)
        }
        static func reviewKeptCommits(_ folder: String) -> String {
            String(format: localized("remote.prs.review.kept.commits %@"), folder)
        }
        static func reviewKeptInUse(_ folder: String) -> String {
            String(format: localized("remote.prs.review.kept.in.use %@"), folder)
        }
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
        static var runHarnessLabel: String { localized("remote.prs.run.harness.label") }
        static var runVendorLabel: String { localized("remote.prs.run.vendor.label") }
        static var runVendorDefault: String { localized("remote.prs.run.vendor.default") }
        static var runFocusLabel: String { localized("remote.prs.run.focus.label") }
        static var runFocusNone: String { localized("remote.prs.run.focus.none") }
        static var runProfileLabel: String { localized("remote.prs.run.profile.label") }
        static var runProfileHarnessDefault: String { localized("remote.prs.run.profile.default") }
        static var runPromptLabel: String { localized("remote.prs.run.prompt.label") }
        static var runCustomize: String { localized("remote.prs.run.customize") }
        static var runCancel: String { localized("remote.prs.run.cancel") }
        static var runInteractiveLabel: String { localized("remote.prs.run.interactive.label") }
        static var runInteractiveHelp: String { localized("remote.prs.run.interactive.help") }
        static var runRefreshDetail: String { localized("remote.prs.run.refresh.detail") }

        // MARK: - PR row context menu additions
        static var copyBranchName: String { localized("remote.prs.copy.branch.name") }
        static var setDefaultFocus: String { localized("remote.prs.set.default.focus") }
        static func defaultFocusSet(_ name: String) -> String {
            String(format: localized("remote.prs.default.focus.set %@"), name)
        }
        static var clearDefaultFocus: String { localized("remote.prs.clear.default.focus") }

        // MARK: - Feed overflow
        static func overflowMore(_ count: Int) -> String {
            String(format: localized("remote.prs.overflow.more %lld"), count)
        }

        // MARK: - Prune
        static var pruneAll: String { localized("remote.prs.prune.all") }
        static var pruneClosedHeader: String { localized("remote.prs.prune.closed.header") }
        static var pruneFocusHeader: String { localized("remote.prs.prune.focus.header") }
        static func pruneFocusTitle(_ count: Int) -> String {
            String(format: localized("remote.prs.prune.focus.title %lld"), count)
        }

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
        static var pruneReasonPROpen: String { localized("remote.prs.prune.reason.pr.open") }
        static var pruneReasonPRClosed: String { localized("remote.prs.prune.reason.pr.closed") }
        static var pruneReasonInUse: String { localized("remote.prs.prune.reason.in.use") }
        static var pruneReasonOrphan: String { localized("remote.prs.prune.reason.orphan") }
        static func pruneFailed(_ names: String) -> String {
            String(format: localized("remote.prs.prune.failed %@"), names)
        }
    }
}

// MARK: - Actions (reviews waiting on the human)

extension Strings {
    enum Actions {
        static var mode: String { localized("actions.mode") }
        static var termqOnly: String { localized("actions.termq.only") }
        static var loadingPR: String { localized("actions.loading.pr") }
        static var checkoutAddingRepository: String { localized("actions.checkout.adding.repository") }
        static var cloneHere: String { localized("actions.clone.here") }
        static func chooseCloneFolder(_ repository: String) -> String {
            String(format: localized("actions.choose.clone.folder %@"), repository)
        }
        static func folderIsNotRepository(_ path: String, _ repository: String) -> String {
            String(format: localized("actions.folder.not.repository %@ %@"), path, repository)
        }
        static func prNotFound(_ number: Int) -> String {
            String(format: localized("actions.pr.not.found %lld"), number)
        }
        static var empty: String { localized("actions.empty") }
        static func loadFailed(_ reason: String) -> String { localized("actions.load.failed %@", reason) }
        static var draft: String { localized("actions.draft") }
        static var copyLink: String { localized("actions.copy.link") }
        static func truncated(_ limit: Int) -> String { localized("actions.truncated %ld", limit) }

        static func waitTitle(_ wait: ReviewWait) -> String {
            switch wait {
            case .today: return localized("actions.wait.today")
            case .thisWeek: return localized("actions.wait.this.week")
            case .thisMonth: return localized("actions.wait.this.month")
            case .older: return localized("actions.wait.older")
            }
        }
    }
}
