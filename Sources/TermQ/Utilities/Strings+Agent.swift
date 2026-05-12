import Foundation
import SwiftUI

// MARK: - Settings.Agent

extension Strings.Settings {
    enum Agent {
        static var sectionTitle: String { localized("settings.agent.section") }
        static var description: String { localized("settings.agent.description") }
        static var enableAgentTab: String { localized("settings.agent.enable.tab") }
        static var enableAgentTabHelp: String { localized("settings.agent.enable.tab.help") }
    }
}

// MARK: - Inspector.Agent

extension Strings {
    enum Inspector {
        enum Agent {
            static var lastSensors: String { localized("inspector.agent.last.sensors") }
            static var trajectory: String { localized("inspector.agent.trajectory") }
            static var trajectoryEmpty: String { localized("inspector.agent.trajectory.empty") }
            static var trajectoryEmptyConfigure: String {
                localized("inspector.agent.trajectory.empty.configure")
            }
            static var trajectoryEmptyRun: String { localized("inspector.agent.trajectory.empty.run") }
            static func turn(_ n: Int) -> String { String(format: localized("inspector.agent.turn"), n) }
            static var sensorsAllPassed: String { localized("inspector.agent.sensors.all.passed") }
            static func sensorsFailed(_ n: Int) -> String {
                String(format: localized("inspector.agent.sensors.failed"), n)
            }
            static var editSensors: String { localized("inspector.agent.edit.sensors") }
            static func turnApprovalTitle(_ n: Int) -> String {
                String(format: localized("inspector.agent.turn.approval.title"), n)
            }
            static var turnApprovalSend: String { localized("inspector.agent.turn.approval.send") }
            static var turnApprovalReset: String { localized("inspector.agent.turn.approval.reset") }
        }
    }
}

// MARK: - OverlayEditor

extension Strings {
    enum OverlayEditor {
        static var title: String { localized("overlay.editor.title") }
        static var loading: String { localized("overlay.editor.loading") }
        static var noSensors: String { localized("overlay.editor.no.sensors") }
        static var roleLabel: String { localized("overlay.editor.role.label") }
        static var roleInherited: String { localized("overlay.editor.role.inherited") }
        static var promptHarnessLabel: String { localized("overlay.editor.prompt.harness.label") }
        static var promptOverrideLabel: String { localized("overlay.editor.prompt.override.label") }
        static var promptOverridePlaceholder: String {
            localized("overlay.editor.prompt.override.placeholder")
        }
        static var sourceKindCommand: String { localized("overlay.editor.source.kind.command") }
        static var sourceKindFiles: String { localized("overlay.editor.source.kind.files") }
        static var sourceKindFocus: String { localized("overlay.editor.source.kind.focus") }
        static var save: String { localized("overlay.editor.save") }
        static var cancel: String { localized("overlay.editor.cancel") }
        static var errorYnhNotReady: String { localized("overlay.editor.error.ynh.not.ready") }
    }
}

// MARK: - Fleet

extension Strings {
    enum Fleet {
        static var sidebarTitle: String { localized("fleet.sidebar.title") }
        static var newFleetHelp: String { localized("fleet.new.help") }
        static var emptyTitle: String { localized("fleet.empty.title") }
        static var emptyBody: String { localized("fleet.empty.body") }
        static var launchTitle: String { localized("fleet.launch.title") }
        static var sectionConfig: String { localized("fleet.launch.section.config") }
        static var sectionTask: String { localized("fleet.launch.section.task") }
        static var fieldHarness: String { localized("fleet.launch.field.harness") }
        static var fieldHarnessPlaceholder: String { localized("fleet.launch.field.harness.placeholder") }
        static var fieldSessions: String { localized("fleet.launch.field.sessions") }
        static var fieldBaseWorktree: String { localized("fleet.launch.field.base.worktree") }
        static var fieldBaseWorktreePlaceholder: String {
            localized("fleet.launch.field.base.worktree.placeholder")
        }
        static var taskPlaceholder: String { localized("fleet.launch.task.placeholder") }
        static var launch: String { localized("fleet.launch.button") }
        static var cancel: String { localized("fleet.launch.cancel") }
        static var fleetLabel: String { localized("fleet.group.label") }
        static func aggregateRunning(_ running: Int, _ total: Int) -> String {
            String(format: localized("fleet.aggregate.running"), running, total)
        }
        static func aggregateConverged(_ converged: Int, _ total: Int) -> String {
            String(format: localized("fleet.aggregate.converged"), converged, total)
        }
        static func aggregateIdle(_ total: Int) -> String {
            String(format: localized("fleet.aggregate.idle"), total)
        }
        static func promoteWinner(_ title: String) -> String {
            String(format: localized("fleet.promote.winner"), title)
        }
    }
}

// MARK: - Editor.Agent

extension Strings.Editor {
    enum Agent {
        static var tab: String { localized("editor.tab.agent") }
        static var sectionConfig: String { localized("editor.agent.section.config") }
        static var sectionBudget: String { localized("editor.agent.section.budget") }
        static var fieldBackend: String { localized("editor.agent.field.backend") }
        static var fieldMode: String { localized("editor.agent.field.mode") }
        static var fieldInteraction: String { localized("editor.agent.field.interaction") }
        static var fieldMaxTurns: String { localized("editor.agent.field.max.turns") }
        static var fieldMaxTokens: String { localized("editor.agent.field.max.tokens") }
        static var fieldMaxWallMinutes: String { localized("editor.agent.field.max.wall.minutes") }
        static var fieldLoopDriverCommand: String { localized("editor.agent.field.loop.driver.command") }
        static var fieldLoopDriverCommandHelp: String {
            localized("editor.agent.field.loop.driver.command.help")
        }
        static var fieldLoopDriverCommandPlaceholder: String {
            localized("editor.agent.field.loop.driver.command.placeholder")
        }
    }
}
