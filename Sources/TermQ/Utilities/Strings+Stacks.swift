import Foundation
import SwiftUI

// MARK: - Stacks

extension Strings {
    enum Stacks {
        static var enableStacking: String { localized("stacks.enable") }
        static var enableStackingHelp: String { localized("stacks.enable.help") }
        static func enableStackingFailed(_ reason: String) -> String {
            localized("stacks.enable.failed %@", reason)
        }
        static var needsRestack: String { localized("stacks.needs.restack") }
        static var openChangeRequest: String { localized("stacks.open.change.request") }
        static func unpushedCommits(_ count: Int) -> String {
            localized("stacks.unpushed.commits %ld", count)
        }
        static var changeRequestMerged: String { localized("stacks.change.request.merged") }
        static var changeRequestClosed: String { localized("stacks.change.request.closed") }
        static var noChangeRequest: String { localized("stacks.no.change.request") }
        static var disclosureHelp: String { localized("stacks.disclosure.help") }

        // Guarded switch
        static var switchBlockedDirty: String { localized("stacks.switch.blocked.dirty") }
        static var switchBlockedInUse: String { localized("stacks.switch.blocked.in.use") }
        static func switchBlockedElsewhere(_ path: String) -> String {
            localized("stacks.switch.blocked.elsewhere %@", path)
        }
        static var switchHelp: String { localized("stacks.switch.help") }
        static func switchTo(_ branch: String) -> String {
            localized("stacks.switch.to %@", branch)
        }

        // Add branch
        static var addBranch: String { localized("stacks.add.branch") }
        static var addBranchTitle: String { localized("stacks.add.branch.title") }
        static var addBranchNameLabel: String { localized("stacks.add.branch.name.label") }
        static var addBranchNamePlaceholder: String { localized("stacks.add.branch.name.placeholder") }
        static var addBranchTargetLabel: String { localized("stacks.add.branch.target.label") }
        static var addBranchStagedNote: String { localized("stacks.add.branch.staged.note") }
        static var addBranchTrackNote: String { localized("stacks.add.branch.track.note") }
        static var addBranchCreate: String { localized("stacks.add.branch.create") }
        static var addBranchTrack: String { localized("stacks.add.branch.track") }

        // Restack
        static var restackStack: String { localized("stacks.restack.stack") }
        static var restackFromHere: String { localized("stacks.restack.from.here") }

        // Conflicts
        static func conflictBanner(_ count: Int) -> String {
            localized("stacks.conflict.banner %ld", count)
        }
        static var conflictContinue: String { localized("stacks.conflict.continue") }
        static var conflictAbort: String { localized("stacks.conflict.abort") }
        static var conflictHint: String { localized("stacks.conflict.hint") }

        // Submit
        static var submitStack: String { localized("stacks.submit.stack") }
        static var submitBranch: String { localized("stacks.submit.branch") }
        static var submitTitle: String { localized("stacks.submit.title") }
        static var submitButton: String { localized("stacks.submit.button") }
        static var submitDraftToggle: String { localized("stacks.submit.draft.toggle") }
        static var submitUpdateOnlyToggle: String { localized("stacks.submit.update.only.toggle") }
        static var submitWillCreate: String { localized("stacks.submit.will.create") }
        static var submitWillUpdate: String { localized("stacks.submit.will.update") }

        // Sync
        static var syncRepo: String { localized("stacks.sync.repo") }
        static func syncCleaned(_ count: Int, _ names: String) -> String {
            localized("stacks.sync.cleaned %ld %@", count, names)
        }

        // Destroy
        static var destroyStack: String { localized("stacks.destroy.stack") }
        static var destroyStackTitle: String { localized("stacks.destroy.stack.title") }
        static func destroyStackMessage(_ count: Int, _ names: String) -> String {
            localized("stacks.destroy.stack.message %ld %@", count, names)
        }
        static func destroyStackOpenPRWarning(_ count: Int) -> String {
            localized("stacks.destroy.stack.open.pr.warning %ld", count)
        }
        static var destroyStackConfirm: String { localized("stacks.destroy.stack.confirm") }
        static func destroyStackDone(_ count: Int) -> String {
            localized("stacks.destroy.stack.done %ld", count)
        }
        static func destroyStackWorktreeSkipped(_ paths: String) -> String {
            localized("stacks.destroy.stack.worktree.skipped %@", paths)
        }

        // Untrack — the non-destructive counterpart to Destroy. Deliberately worded so
        // the two can never be confused: this one leaves every branch in place.
        static var untrackStack: String { localized("stacks.untrack.stack") }
        static var untrackStackTitle: String { localized("stacks.untrack.stack.title") }
        static func untrackStackMessage(_ count: Int, _ names: String) -> String {
            localized("stacks.untrack.stack.message %ld %@", count, names)
        }
        static var untrackStackConfirm: String { localized("stacks.untrack.stack.confirm") }
        static var untrackStackDone: String { localized("stacks.untrack.stack.done") }

        // Merge Stack — the only action here that lands code on a real branch.
        static var mergeStack: String { localized("stacks.merge.stack") }
        static var mergeStackTitle: String { localized("stacks.merge.stack.title") }
        static func mergeStackMessage(_ count: Int) -> String {
            localized("stacks.merge.stack.message %ld", count)
        }
        static func mergeStackConfirm(_ count: Int) -> String {
            localized("stacks.merge.stack.confirm %ld", count)
        }
        static func mergeStackMethod(_ method: String) -> String {
            localized("stacks.merge.stack.method %@", method)
        }
        static var mergeStackIrreversible: String { localized("stacks.merge.stack.irreversible") }
        static func mergeStackDone(_ count: Int) -> String {
            localized("stacks.merge.stack.done %ld", count)
        }
        static var mergeStackLoading: String { localized("stacks.merge.stack.loading") }
        static var mergeStackNotSubmitted: String { localized("stacks.merge.stack.not.submitted") }
        static var mergeBlockedDraft: String { localized("stacks.merge.blocked.draft") }
        static var mergeBlockedClosed: String { localized("stacks.merge.blocked.closed") }
        static var mergeBlockedMerged: String { localized("stacks.merge.blocked.merged") }
        /// Shown when a draft or closed PR partway up stops the whole stack merging.
        /// The partial merge is deliberately handed to GitHub — see the sheet.
        static func mergeBlockedBy(_ number: String) -> String {
            localized("stacks.merge.blocked.by %@", number)
        }
        static var mergeOpenOnGitHub: String { localized("stacks.merge.open.on.github") }
        static var reviewApproved: String { localized("stacks.review.approved") }
        static var reviewChangesRequested: String { localized("stacks.review.changes.requested") }
        static var reviewRequired: String { localized("stacks.review.required") }
        static var checksPassing: String { localized("stacks.checks.passing") }
        static var checksFailing: String { localized("stacks.checks.failing") }
        static var checksPending: String { localized("stacks.checks.pending") }

        // Link PRs into a Stack — creates pull requests, so it is named for that.
        static var linkStack: String { localized("stacks.link.stack") }
        static var linkStackTitle: String { localized("stacks.link.stack.title") }
        static func linkStackWillCreate(_ count: Int) -> String {
            localized("stacks.link.stack.will.create %ld", count)
        }
        static var linkStackExisting: String { localized("stacks.link.stack.existing") }
        static var linkStackNew: String { localized("stacks.link.stack.new") }
        static func linkStackConfirm(_ count: Int) -> String {
            localized("stacks.link.stack.confirm %ld", count)
        }
        static var linkStackDone: String { localized("stacks.link.stack.done") }

        // Check Out Whole Stack — Remote PRs feed.
        static func checkoutStack(_ count: Int) -> String {
            localized("stacks.checkout.stack %ld", count)
        }
        static func checkoutStackDone(_ count: Int) -> String {
            localized("stacks.checkout.stack.done %ld", count)
        }

        // Sync confirmation — shown only for a provider whose sync reaches the remote.
        static var syncConfirmTitle: String { localized("stacks.sync.confirm.title") }
        static func syncConfirmMessage(_ count: Int, _ names: String) -> String {
            localized("stacks.sync.confirm.message %ld %@", count, names)
        }
        static var syncConfirmButton: String { localized("stacks.sync.confirm.button") }

        // PR targeting
        static func baseMismatch(_ prBase: String, _ parent: String) -> String {
            localized("stacks.base.mismatch %@ %@", prBase, parent)
        }

        // Mutation outcomes
        static var restackUpToDate: String { localized("stacks.restack.up.to.date") }
        static func restackDone(_ count: Int) -> String {
            localized("stacks.restack.done %ld", count)
        }
        static var syncClean: String { localized("stacks.sync.clean") }
        static func submitDone(_ created: Int, _ updated: Int) -> String {
            localized("stacks.submit.done %ld %ld", created, updated)
        }

        // Break-out + orchestration
        static var breakOut: String { localized("stacks.break.out") }
        static func skippedNotice(_ lines: String) -> String {
            localized("stacks.skipped.notice %@", lines)
        }
        static func skippedDirty(_ branch: String, _ path: String) -> String {
            localized("stacks.skipped.dirty %@ %@", branch, path)
        }
        static func skippedInUse(_ branch: String, _ path: String) -> String {
            localized("stacks.skipped.in.use %@ %@", branch, path)
        }

        // Inventory context menu
        static var copyBranchName: String { localized("stacks.copy.branch.name") }
        static var revealWorktree: String { localized("stacks.reveal.worktree") }

        static func anchoredBadgeHelp(_ name: String) -> String {
            localized("stacks.anchored.badge.help %@", name)
        }

        static func partOfStack(_ root: String) -> String {
            localized("stacks.part.of.stack %@", root)
        }

        // Stacks inventory section
        static var sectionHeader: String { localized("stacks.section.header") }
        static func checkedOutAt(_ path: String) -> String {
            localized("stacks.checked.out.at %@", path)
        }
        static var anchorHelp: String { localized("stacks.anchor.help") }
        static var groupNewWorktree: String { localized("stacks.group.new.worktree") }

        // Round-3: launch menus
        static var newBranchBefore: String { localized("stacks.new.branch.before") }
        static var newBranchAfter: String { localized("stacks.new.branch.after") }
        static func newBranchInsertBelowNote(_ branch: String) -> String {
            localized("stacks.new.branch.insert.below.note %@", branch)
        }
        static func newBranchInsertAboveNote(_ branch: String) -> String {
            localized("stacks.new.branch.insert.above.note %@", branch, branch)
        }
        static var mainWorktreeNotFound: String { localized("stacks.main.worktree.not.found") }

        // Round-3 addendum: stack creation entry points
        static var newStack: String { localized("stacks.new.stack") }
        static var newStackTitle: String { localized("stacks.new.stack.title") }
        static var newStackNameLabel: String { localized("stacks.new.stack.name.label") }
        static var newStackNamePlaceholder: String { localized("stacks.new.stack.name.placeholder") }
        static var newStackBaseLabel: String { localized("stacks.new.stack.base.label") }
        static var newStackButton: String { localized("stacks.new.stack.button") }
        static var newStackNote: String { localized("stacks.new.stack.note") }
        static var startStackCheckbox: String { localized("stacks.start.stack.checkbox") }

        // New Stack modes
        static var newStackModeDefault: String { localized("stacks.new.stack.mode.default") }
        static var newStackModeIntegration: String { localized("stacks.new.stack.mode.integration") }
        static var newStackStackNameLabel: String { localized("stacks.new.stack.stack.name.label") }
        static func newStackIntegrationPreview(_ branch: String) -> String {
            localized("stacks.new.stack.integration.preview %@", branch)
        }
        static var newStackFirstBranchLabel: String { localized("stacks.new.stack.first.branch.label") }
        static var newStackFirstBranchEmptyHint: String {
            localized("stacks.new.stack.first.branch.empty.hint")
        }
        static var newStackFirstBranchFilledHint: String {
            localized("stacks.new.stack.first.branch.filled.hint")
        }
        static var newStackIntegrationNote: String { localized("stacks.new.stack.integration.note") }
        static func newStackNameExists(_ branch: String) -> String {
            localized("stacks.new.stack.name.exists %@", branch)
        }
    }
}
