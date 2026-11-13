import Foundation
import TermQShared

// MARK: - Wheelhouses sidebar tab

extension Strings {
    enum Wheelhouse {
        static var title: String { localized("wheelhouse.title") }
        static var allWheelhouses: String { localized("wheelhouse.all") }
        static var refreshHelp: String { localized("wheelhouse.refresh.help") }
        static var emptyTitle: String { localized("wheelhouse.empty.title") }
        static var emptyMessage: String { localized("wheelhouse.empty.message") }
        static func seatCount(_ count: Int) -> String { localized("wheelhouse.seat.count %ld", count) }
        static func loadFailed(_ name: String) -> String { localized("wheelhouse.load.failed %@", name) }
        static var revealInFinder: String { localized("wheelhouse.reveal.in.finder") }
        static var copyCommand: String { localized("wheelhouse.copy.command") }
        static var addWheelhouse: String { localized("wheelhouse.add") }
        static var addPanelMessage: String { localized("wheelhouse.add.panel.message") }
        static var addPathPlaceholder: String { localized("wheelhouse.add.path.placeholder") }
        static var addChooseFolder: String { localized("wheelhouse.add.choose.folder") }
        static var addButton: String { localized("wheelhouse.add.button") }
        static func addNoFolder(_ path: String) -> String { localized("wheelhouse.add.no.folder %@", path) }
        static var addFailedTitle: String { localized("wheelhouse.add.failed.title") }
        static func notAWheelhouse(_ name: String) -> String { localized("wheelhouse.not.a.wheelhouse %@", name) }
        static var workUnavailable: String { localized("wheelhouse.work.unavailable") }
        static var unbornHelp: String { localized("wheelhouse.unborn.help") }
        static func waitingOn(_ pr: String) -> String { localized("wheelhouse.waiting.on %@", pr) }
        static var showTerminal: String { localized("wheelhouse.show.terminal") }
        static var statusIdle: String { localized("wheelhouse.status.idle") }
        static var workingHelp: String { localized("wheelhouse.working.help") }
        static var pin: String { localized("wheelhouse.pin") }
        static var keepOnStage: String { localized("wheelhouse.keep.on.stage") }
        static var zoomTerminal: String { localized("wheelhouse.zoom.terminal") }
        static var install: String { localized("wheelhouse.install") }
        static var actionRequired: String { localized("wheelhouse.action.required") }
        static var actionRequiredHelp: String { localized("wheelhouse.action.required.help") }
        static func fixTitle(_ seat: String) -> String { localized("wheelhouse.fix.title %@", seat) }
        static var fixAllClear: String { localized("wheelhouse.fix.all.clear") }
        static var issueNotInstalled: String { localized("wheelhouse.issue.not.installed") }
        static func issueNotInstalledDetail(_ command: String) -> String {
            localized("wheelhouse.issue.not.installed.detail %@", command)
        }
        static func issueNotCommitted(_ names: String) -> String {
            localized("wheelhouse.issue.not.committed %@", names)
        }
        static var issueNotCommittedDetail: String { localized("wheelhouse.issue.not.committed.detail") }
        static func issueMissing(_ names: String) -> String { localized("wheelhouse.issue.missing %@", names) }
        static var issueMissingDetail: String { localized("wheelhouse.issue.missing.detail") }
        static var issueLaunchFailed: String { localized("wheelhouse.issue.launch.failed") }
        static var copyCommitCommand: String { localized("wheelhouse.copy.commit.command") }
        static var tryAgain: String { localized("wheelhouse.try.again") }
        static var openAnyway: String { localized("wheelhouse.open.anyway") }
        /// "Install (needs io, titan first)".
        static func needsFirst(_ action: String, _ names: String) -> String {
            localized("wheelhouse.needs.first %@ %@", action, names)
        }
        static var showQuickTerminals: String { localized("wheelhouse.show.quick.terminals") }
        static var hideQuickTerminals: String { localized("wheelhouse.hide.quick.terminals") }
        static var exitZoom: String { localized("wheelhouse.exit.zoom") }
        static func seatHarnessTitle(_ seat: String, _ wheelhouse: String) -> String {
            localized("wheelhouse.seat.harness.title %@ %@", seat, wheelhouse)
        }
        static func seatHarnessRunning(_ seat: String) -> String {
            localized("wheelhouse.seat.harness.running %@", seat)
        }
        static func seatHarnessIdle(_ seat: String) -> String { localized("wheelhouse.seat.harness.idle %@", seat) }
        static func restartSeat(_ seat: String) -> String { localized("wheelhouse.restart.seat %@", seat) }
        static func stepHandoff(_ seat: String) -> String { localized("wheelhouse.step.handoff %@", seat) }
        static func stepRestart(_ seat: String) -> String { localized("wheelhouse.step.restart %@", seat) }
        static func seatHarnessHandingOff(_ seat: String) -> String {
            localized("wheelhouse.seat.harness.handing.off %@", seat)
        }
        static var restartSeatHelp: String { localized("wheelhouse.restart.seat.help") }
        static var unpin: String { localized("wheelhouse.unpin") }

        // Stage
        static var stageTitle: String { localized("wheelhouse.stage.title") }
        static var enterFocus: String { localized("wheelhouse.focus.enter") }
        static var exitFocus: String { localized("wheelhouse.focus.exit") }
        static var focusHelp: String { localized("wheelhouse.focus.help") }
        static var bringOnStage: String { localized("wheelhouse.bring.on.stage") }
        static var takeOffStage: String { localized("wheelhouse.take.off.stage") }
        static var smartCloseHelp: String { localized("wheelhouse.smart.close.help") }
        static var needsYou: String { localized("wheelhouse.needs.you") }
        static var nobodyWaiting: String { localized("wheelhouse.nobody.waiting") }
        static func moreWaiting(_ count: Int) -> String { localized("wheelhouse.more.waiting %ld", count) }
        static var rangTheBell: String { localized("wheelhouse.rang.the.bell") }
        static var justNow: String { localized("wheelhouse.just.now") }
        static var seatActions: String { localized("wheelhouse.seat.actions") }
        static var emptyStageTitle: String { localized("wheelhouse.stage.empty.title") }
        static var emptyStageMessage: String { localized("wheelhouse.stage.empty.message") }

        // Seat actions
        static var birth: String { localized("wheelhouse.action.birth") }
        static var handoff: String { localized("wheelhouse.action.handoff") }
        static var closeTerminal: String { localized("wheelhouse.action.close.terminal") }
        static var harnessDetails: String { localized("wheelhouse.action.harness.details") }
        static var askToFocus: String { localized("wheelhouse.action.ask.focus") }

        // Group headers and their hints
        static func groupLabel(_ group: WheelhouseGroup) -> String {
            switch group {
            case .desk: return localized("wheelhouse.group.desk")
            case .crew: return localized("wheelhouse.group.crew")
            case .standing: return localized("wheelhouse.group.standing")
            case .workers: return localized("wheelhouse.group.workers")
            case .other(let raw):
                return raw.isEmpty ? localized("wheelhouse.group.other") : WheelhouseRole(rawValue: raw).titleCasedSlug
            }
        }

        static func groupHint(_ group: WheelhouseGroup) -> String? {
            switch group {
            case .desk: return localized("wheelhouse.group.desk.hint")
            case .crew: return localized("wheelhouse.group.crew.hint")
            case .standing: return localized("wheelhouse.group.standing.hint")
            case .workers: return localized("wheelhouse.group.workers.hint")
            case .other: return nil
            }
        }

        // Role labels
        static func roleLabel(_ role: WheelhouseRole) -> String {
            switch role {
            case .desk: return localized("wheelhouse.role.desk")
            case .designer: return localized("wheelhouse.role.designer")
            case .reviewer: return localized("wheelhouse.role.reviewer")
            case .dispatcher: return localized("wheelhouse.role.dispatcher")
            case .ciWatcher: return localized("wheelhouse.role.ci.watcher")
            case .releaser: return localized("wheelhouse.role.releaser")
            case .verifier: return localized("wheelhouse.role.verifier")
            case .programmeManager: return localized("wheelhouse.role.programme.manager")
            case .tutor: return localized("wheelhouse.role.tutor")
            case .specialistWorker, .worker: return localized("wheelhouse.role.builder")
            case .other: return role.titleCasedSlug
            }
        }

        // Quick Terminals
        static func quickTerminalTitle(_ number: Int) -> String {
            localized("wheelhouse.quick.terminal.title %ld", number)
        }
        static func quickTerminalHelp(_ number: Int, _ seat: String) -> String {
            localized("wheelhouse.quick.terminal.help %ld %@", number, seat)
        }

        // Inbox
        static var inboxTitle: String { localized("wheelhouse.inbox.title") }
        static func inboxHelp(_ names: String) -> String { localized("wheelhouse.inbox.help %@", names) }
        static var inboxEmpty: String { localized("wheelhouse.inbox.empty") }
        static var inboxUnavailable: String { localized("wheelhouse.inbox.unavailable") }
        static func inboxFor(_ name: String) -> String { localized("wheelhouse.inbox.for %@", name) }
        static func inboxFrom(_ seat: String) -> String { localized("wheelhouse.inbox.from %@", seat) }
        static func inboxUnblocks(_ count: Int) -> String { localized("wheelhouse.inbox.unblocks %ld", count) }
        static var inboxOpenLink: String { localized("wheelhouse.inbox.open.link") }
        static var inboxCopyId: String { localized("wheelhouse.inbox.copy.id") }
        static var inboxSendTo: String { localized("wheelhouse.inbox.send.to") }
        static func inboxSendPrompt(_ id: String, _ title: String) -> String {
            localized("wheelhouse.inbox.send.prompt %@ %@", id, title)
        }
        static var inboxShowDetails: String { localized("wheelhouse.inbox.show.details") }
        static var inboxHideDetails: String { localized("wheelhouse.inbox.hide.details") }
        static var inboxComment: String { localized("wheelhouse.inbox.comment") }
        static var inboxClose: String { localized("wheelhouse.inbox.close") }
        static var inboxCommentButton: String { localized("wheelhouse.inbox.comment.button") }
        static var inboxCloseButton: String { localized("wheelhouse.inbox.close.button") }
        static var inboxCommentPlaceholder: String { localized("wheelhouse.inbox.comment.placeholder") }
        static var inboxClosePlaceholder: String { localized("wheelhouse.inbox.close.placeholder") }
        static var inboxRespondFailed: String { localized("wheelhouse.inbox.respond.failed") }
        static var inboxRefreshHelp: String { localized("wheelhouse.inbox.refresh.help") }
        static var inboxFilterAll: String { localized("wheelhouse.inbox.filter.all") }
        static func inboxFilterHelp(_ kind: String) -> String { localized("wheelhouse.inbox.filter.help %@", kind) }
        static func inboxSentTo(_ seat: String) -> String { localized("wheelhouse.inbox.sent.to %@", seat) }

        /// Role label plus specialities, such as "Builder · ynh".
        static func roleLabel(for seat: WheelhouseSeat) -> String? {
            guard let role = seat.effectiveRole else { return nil }
            let base = roleLabel(role)
            let repos = seat.repositories
            switch role {
            case .worker where repos.isEmpty:
                return localized("wheelhouse.role.builder.any")
            case _ where repos.isEmpty:
                return base
            default:
                return ([base] + repos).joined(separator: " · ")
            }
        }
    }
}

// MARK: - Settings.Wheelhouse

extension Strings.Settings {
    enum Wheelhouse {
        static var enableTab: String { localized("settings.wheelhouse.enable.tab") }
        static var enableTabHelp: String { localized("settings.wheelhouse.enable.tab.help") }
        static var quickTerminalPlacement: String { localized("settings.wheelhouse.quick.terminal.placement") }
        static var quickTerminalPlacementHelp: String {
            localized("settings.wheelhouse.quick.terminal.placement.help")
        }
        static var placementStaged: String { localized("settings.wheelhouse.placement.staged") }
        static var placementSplit: String { localized("settings.wheelhouse.placement.split") }
        static var inboxHumanName: String { localized("settings.wheelhouse.inbox.human.name") }
        static var inboxHumanNameHelp: String { localized("settings.wheelhouse.inbox.human.name.help") }
        static var inboxOwnName: String { localized("settings.wheelhouse.inbox.own.name") }
        static var inboxOwnNameHelp: String { localized("settings.wheelhouse.inbox.own.name.help") }
    }
}
