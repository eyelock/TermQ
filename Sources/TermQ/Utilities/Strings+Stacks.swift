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
    }
}
