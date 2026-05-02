extension Strings {
    // MARK: - Restore
    enum Restore {
        static var welcome: String { localized("restore.welcome") }
        static var foundBackup: String { localized("restore.found.backup") }
        static var question: String { localized("restore.question") }
        static var startFresh: String { localized("restore.start.fresh") }
        static var restoring: String { localized("restore.restoring") }
        static var button: String { localized("restore.button") }
    }

    // MARK: - Uninstall
    enum Uninstall {
        static var title: String { localized("uninstall.title") }
        static var sectionHeader: String { localized("uninstall.section.header") }
        static var description: String { localized("uninstall.description") }
        static var buttonTitle: String { localized("uninstall.button.title") }
        static var willRemove: String { localized("uninstall.will.remove") }
        static var cliTool: String { localized("uninstall.cli.tool") }
        static var mcpServer: String { localized("uninstall.mcp.server") }
        static var appData: String { localized("uninstall.app.data") }
        static var backupWarning: String { localized("uninstall.backup.warning") }
        static var continueButton: String { localized("uninstall.continue.button") }
        static var creatingBackup: String { localized("uninstall.creating.backup") }
        static var backupLocation: String { localized("uninstall.backup.location") }
        static var backupComplete: String { localized("uninstall.backup.complete") }
        static var dataBackedUp: String { localized("uninstall.data.backed.up") }
        static var readyRemove: String { localized("uninstall.ready.remove") }
        static var processing: String { localized("uninstall.processing") }
        static var complete: String { localized("uninstall.complete") }
        static var toComplete: String { localized("uninstall.to.complete") }
        static var dragToTrash: String { localized("uninstall.drag.to.trash") }
        static var backupPreserved: String { localized("uninstall.backup.preserved") }
        static var done: String { localized("uninstall.done") }
        static var removedCli: String { localized("uninstall.removed.cli") }
        static var removedMcp: String { localized("uninstall.removed.mcp") }
        static var removedData: String { localized("uninstall.removed.data") }
        static func errorData(_ error: String) -> String {
            localized("uninstall.error.data %@", error)
        }
    }
}
