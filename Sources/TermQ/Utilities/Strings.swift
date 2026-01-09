import Foundation
import SwiftUI

/// Centralized string localization for TermQ
/// Usage: Text(Strings.board.columnOptions)
enum Strings {
    // MARK: - App
    static let appName = String(localized: "app.name")

    // MARK: - Board View
    enum Board {
        static let columnOptions = String(localized: "board.column.options")
        static let columnRename = String(localized: "board.column.rename")
        static let columnDelete = String(localized: "board.column.delete")
        static let columnDeleteDisabled = String(localized: "board.column.delete.disabled")
        static let addTerminal = String(localized: "board.column.add.terminal")
        static let addTerminalHelp = String(localized: "board.column.add.terminal.help")
    }

    // MARK: - Terminal Card
    enum Card {
        static let pin = String(localized: "card.pin")
        static let unpin = String(localized: "card.unpin")
        static let running = String(localized: "card.running")
        static let open = String(localized: "card.open")
        static let edit = String(localized: "card.edit")
        static let delete = String(localized: "card.delete")
    }

    // MARK: - Expanded Terminal View
    enum Terminal {
        static let ended = String(localized: "terminal.ended")
        static let restart = String(localized: "terminal.restart")
        static let restartHelp = String(localized: "terminal.restart.help")
        static let current = String(localized: "terminal.current")
        static func switchTo(_ name: String) -> String {
            String(format: NSLocalizedString("terminal.switch.to", comment: ""), name)
        }
    }

    // MARK: - Toolbar
    enum Toolbar {
        static let back = String(localized: "toolbar.back")
        static let moveTo = String(localized: "toolbar.move.to")
        static let newQuick = String(localized: "toolbar.new.quick")
        static let newQuickShortcut = String(localized: "toolbar.new.quick.shortcut")
        static let edit = String(localized: "toolbar.edit")
        static let editShortcut = String(localized: "toolbar.edit.shortcut")
        static let pin = String(localized: "toolbar.pin")
        static let unpin = String(localized: "toolbar.unpin")
        static let delete = String(localized: "toolbar.delete")
        static let add = String(localized: "toolbar.add")
    }

    // MARK: - Menu Commands
    enum Menu {
        static let newTerminalQuick = String(localized: "menu.new.terminal.quick")
        static let newTerminal = String(localized: "menu.new.terminal")
        static let newTerminalDialog = String(localized: "menu.new.terminal.dialog")
        static let newColumn = String(localized: "menu.new.column")
        static let back = String(localized: "menu.back")
        static let togglePin = String(localized: "menu.toggle.pin")
        static let nextPinned = String(localized: "menu.next.pinned")
        static let previousPinned = String(localized: "menu.previous.pinned")
    }

    // MARK: - Delete Confirmation
    enum Delete {
        static let title = String(localized: "delete.title")
        static func message(_ name: String) -> String {
            String(format: NSLocalizedString("delete.message", comment: ""), name)
        }
        static let cancel = String(localized: "delete.cancel")
        static let confirm = String(localized: "delete.confirm")
    }

    // MARK: - Card Editor
    enum Editor {
        static let titleNew = String(localized: "editor.title.new")
        static let titleEdit = String(localized: "editor.title.edit")
        static let fieldName = String(localized: "editor.field.name")
        static let fieldNamePlaceholder = String(localized: "editor.field.name.placeholder")
        static let fieldDescription = String(localized: "editor.field.description")
        static let fieldDescriptionPlaceholder = String(localized: "editor.field.description.placeholder")
        static let fieldColumn = String(localized: "editor.field.column")
        static let fieldDirectory = String(localized: "editor.field.directory")
        static let fieldTags = String(localized: "editor.field.tags")
        static let tagAdd = String(localized: "editor.tag.add")
        static let tagKeyPlaceholder = String(localized: "editor.tag.key.placeholder")
        static let tagValuePlaceholder = String(localized: "editor.tag.value.placeholder")
        static let cancel = String(localized: "editor.cancel")
        static let save = String(localized: "editor.save")
        static let saveOpen = String(localized: "editor.save.open")
    }

    // MARK: - Column Editor
    enum ColumnEditor {
        static let title = String(localized: "column.editor.title")
        static let fieldName = String(localized: "column.editor.field.name")
        static let fieldNamePlaceholder = String(localized: "column.editor.field.name.placeholder")
        static let fieldColor = String(localized: "column.editor.field.color")
        static let cancel = String(localized: "column.editor.cancel")
        static let save = String(localized: "column.editor.save")
    }

    // MARK: - Settings
    enum Settings {
        static let title = String(localized: "settings.title")
        static let cliTitle = String(localized: "settings.cli.title")
        static let cliDescription = String(localized: "settings.cli.description")
        static let cliPath = String(localized: "settings.cli.path")
        static let cliInstall = String(localized: "settings.cli.install")
        static let cliUninstall = String(localized: "settings.cli.uninstall")
        static let cliInstalled = String(localized: "settings.cli.installed")
        static let cliNotInstalled = String(localized: "settings.cli.not.installed")
        static let cliUsage = String(localized: "settings.cli.usage")
    }
}
