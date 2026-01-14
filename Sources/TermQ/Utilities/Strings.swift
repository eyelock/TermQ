import Foundation
import SwiftUI

/// Centralized string localization for TermQ
/// Usage: Text(Strings.Board.columnOptions)
enum Strings {
    // MARK: - App
    static let appName = String(localized: "app.name")

    // MARK: - Common
    enum Common {
        static let ok = String(localized: "common.ok")
        static let cancel = String(localized: "common.cancel")
        static let save = String(localized: "common.save")
        static let delete = String(localized: "common.delete")
        static let edit = String(localized: "common.edit")
        static let close = String(localized: "common.close")
        static let add = String(localized: "common.add")
        static let reinstall = String(localized: "common.reinstall")
        static let uninstall = String(localized: "common.uninstall")
        static let installed = String(localized: "common.installed")
        static let browse = String(localized: "common.browse")
        static let apply = String(localized: "common.apply")
        static let preview = String(localized: "common.preview")
    }

    // MARK: - Board View
    enum Board {
        static let columnOptions = String(localized: "board.column.options")
        static let columnRename = String(localized: "board.column.rename")
        static let columnDelete = String(localized: "board.column.delete")
        static let columnDeleteDisabled = String(localized: "board.column.delete.disabled")
        static let addTerminal = String(localized: "board.column.add.terminal")
        static let addTerminalHelp = String(localized: "board.column.add.terminal.help")
        static let editColumn = String(localized: "board.column.edit")
    }

    // MARK: - Terminal Card
    enum Card {
        static let pin = String(localized: "card.pin")
        static let unpin = String(localized: "card.unpin")
        static let running = String(localized: "card.running")
        static let open = String(localized: "card.open")
        static let edit = String(localized: "card.edit")
        static let delete = String(localized: "card.delete")
        static let wired = String(localized: "card.wired")
        static let wiredHelp = String(localized: "card.wired.help")
        static let needsAttention = String(localized: "card.needs.attention")
        static let processing = String(localized: "card.processing")
    }

    // MARK: - Expanded Terminal View
    enum Terminal {
        static let ended = String(localized: "terminal.ended")
        static let restart = String(localized: "terminal.restart")
        static let restartHelp = String(localized: "terminal.restart.help")
        static let current = String(localized: "terminal.current")
        static let editHelp = String(localized: "terminal.edit.help")
        static let closeTabHelp = String(localized: "terminal.close.tab.help")
        static func switchTo(_ name: String) -> String {
            String(localized: "terminal.switch.to \(name)")
        }
        static func tabHelp(_ title: String, _ column: String) -> String {
            String(localized: "terminal.tab.help \(title) \(column)")
        }
    }

    // MARK: - Toolbar
    enum Toolbar {
        static let back = String(localized: "toolbar.back")
        static let backHelp = String(localized: "toolbar.back.help")
        static let moveTo = String(localized: "toolbar.move.to")
        static let newQuick = String(localized: "toolbar.new.quick")
        static let newQuickHelp = String(localized: "toolbar.new.quick.help")
        static let edit = String(localized: "toolbar.edit")
        static let editHelp = String(localized: "toolbar.edit.help")
        static let pin = String(localized: "toolbar.pin")
        static let pinHelp = String(localized: "toolbar.pin.help")
        static let unpin = String(localized: "toolbar.unpin")
        static let unpinHelp = String(localized: "toolbar.unpin.help")
        static let delete = String(localized: "toolbar.delete")
        static let deleteHelp = String(localized: "toolbar.delete.help")
        static let add = String(localized: "toolbar.add")
        static let addHelp = String(localized: "toolbar.add.help")
        static let openTerminalApp = String(localized: "toolbar.open.terminal.app")
        static let openTerminalAppHelp = String(localized: "toolbar.open.terminal.app.help")
        static let newTerminal = String(localized: "toolbar.new.terminal")
        static let newColumn = String(localized: "toolbar.new.column")
        static func binCount(_ count: Int) -> String {
            String(localized: "toolbar.bin.count \(count)")
        }
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
        static let moveToBin = String(localized: "delete.move.to.bin")
        static func message(_ name: String) -> String {
            String(localized: "delete.message \(name)")
        }
        static func binMessage(_ name: String) -> String {
            String(localized: "delete.bin.message \(name)")
        }
        static let cancel = String(localized: "delete.cancel")
        static let confirm = String(localized: "delete.confirm")
        static let permanent = String(localized: "delete.permanent")
    }

    // MARK: - Card Editor
    enum Editor {
        static let titleNew = String(localized: "editor.title.new")
        static let titleEdit = String(localized: "editor.title.edit")
        static let tabGeneral = String(localized: "editor.tab.general")
        static let tabAdvanced = String(localized: "editor.tab.advanced")

        // General tab
        static let sectionDetails = String(localized: "editor.section.details")
        static let fieldName = String(localized: "editor.field.name")
        static let fieldNamePlaceholder = String(localized: "editor.field.name.placeholder")
        static let fieldDescription = String(localized: "editor.field.description")
        static let fieldDescriptionPlaceholder = String(localized: "editor.field.description.placeholder")
        static let fieldColumn = String(localized: "editor.field.column")
        static let fieldBadges = String(localized: "editor.field.badges")
        static let fieldBadgesPlaceholder = String(localized: "editor.field.badges.placeholder")
        static let fieldBadgesHelp = String(localized: "editor.field.badges.help")

        // Appearance section
        static let sectionAppearance = String(localized: "editor.section.appearance")
        static let fieldTheme = String(localized: "editor.field.theme")
        static let fieldThemeDefault = String(localized: "editor.field.theme.default")
        static let fieldFontSize = String(localized: "editor.field.font.size")
        static let fontPreview = String(localized: "editor.font.preview")

        // Terminal section
        static let sectionTerminal = String(localized: "editor.section.terminal")
        static let fieldDirectory = String(localized: "editor.field.directory")
        static let fieldDirectoryHelp = String(localized: "editor.field.directory.help")
        static let fieldShell = String(localized: "editor.field.shell")
        static let fieldShellHelp = String(localized: "editor.field.shell.help")

        // Automation section
        static let sectionAutomation = String(localized: "editor.section.automation")
        static let fieldInitCommand = String(localized: "editor.field.init.command")
        static let fieldInitCommandHelp = String(localized: "editor.field.init.command.help")
        static let fieldSafePaste = String(localized: "editor.field.safe.paste")
        static let fieldSafePasteHelp = String(localized: "editor.field.safe.paste.help")
        static let fieldAllowAutorun = String(localized: "editor.field.allow.autorun")
        static let fieldAllowAutorunHelp = String(localized: "editor.field.allow.autorun.help")
        static let fieldAutorunDisabledGlobally = String(localized: "editor.field.autorun.disabled.globally")
        static let fieldAutorunEnableHint = String(localized: "editor.field.autorun.enable.hint")

        // Tags section
        static let sectionTags = String(localized: "editor.section.tags")
        static let fieldTags = String(localized: "editor.field.tags")
        static let tagAdd = String(localized: "editor.tag.add")
        static let tagKeyPlaceholder = String(localized: "editor.tag.key.placeholder")
        static let tagValuePlaceholder = String(localized: "editor.tag.value.placeholder")
        static let tagsHelp = String(localized: "editor.tags.help")

        // Agent Configuration section
        static let sectionAgent = String(localized: "editor.section.agent")
        static let fieldTerminalAllowsAutorun = String(localized: "editor.field.terminal.allows.autorun")
        static let fieldPersistentContext = String(localized: "editor.field.persistent.context")
        static let fieldPersistentContextHelp = String(localized: "editor.field.persistent.context.help")
        static let fieldNextAction = String(localized: "editor.field.next.action")
        static let fieldNextActionHelp = String(localized: "editor.field.next.action.help")

        // Command Generator section
        static let sectionCommandGenerator = String(localized: "editor.section.command.generator")
        static let fieldApplyToInitCommand = String(localized: "editor.field.apply.to.init.command")
        static let fieldApplyToInitCommandHelp = String(localized: "editor.field.apply.to.init.command.help")
        static let noLlmPromptWarning = String(localized: "editor.no.llm.prompt.warning")
        static let nonInteractiveNote = String(localized: "editor.non.interactive.note")

        static let cancel = String(localized: "editor.cancel")
        static let save = String(localized: "editor.save")
        static let saveOpen = String(localized: "editor.save.open")
    }

    // MARK: - Column Editor
    enum ColumnEditor {
        static let titleNew = String(localized: "column.editor.title.new")
        static let titleEdit = String(localized: "column.editor.title.edit")
        static let fieldName = String(localized: "column.editor.field.name")
        static let fieldNamePlaceholder = String(localized: "column.editor.field.name.placeholder")
        static let fieldDescription = String(localized: "column.editor.field.description")
        static let fieldDescriptionPlaceholder = String(localized: "column.editor.field.description.placeholder")
        static let fieldColor = String(localized: "column.editor.field.color")
        static let cancel = String(localized: "column.editor.cancel")
        static let save = String(localized: "column.editor.save")
    }

    // MARK: - Bin
    enum Bin {
        static let title = String(localized: "bin.title")
        static let empty = String(localized: "bin.empty")
        static let emptyButton = String(localized: "bin.empty.button")
        static let closeHelp = String(localized: "bin.close.help")
        static let restoreHelp = String(localized: "bin.restore.help")
        static let deleteHelp = String(localized: "bin.delete.help")
        static func deleted(_ date: String) -> String {
            String(localized: "bin.deleted \(date)")
        }
        static func daysRemaining(_ days: Int) -> String {
            String(localized: "bin.days.remaining \(days)")
        }
    }

    // MARK: - Settings
    enum Settings {
        static let title = String(localized: "settings.title")
        static let tabGeneral = String(localized: "settings.tab.general")
        static let tabTools = String(localized: "settings.tab.tools")

        // General - Terminal section
        static let sectionTerminal = String(localized: "settings.section.terminal")
        static let fieldTheme = String(localized: "settings.field.theme")
        static let fieldThemeHelp = String(localized: "settings.field.theme.help")
        static let fieldCopyOnSelect = String(localized: "settings.field.copy.on.select")
        static let fieldCopyOnSelectHelp = String(localized: "settings.field.copy.on.select.help")

        // General - Bin section
        static let sectionBin = String(localized: "settings.section.bin")
        static func autoEmpty(_ days: Int) -> String {
            String(localized: "settings.auto.empty \(days)")
        }
        static let autoEmptyHelp = String(localized: "settings.auto.empty.help")
        static let binEmpty = String(localized: "settings.bin.empty")
        static func binItems(_ count: Int) -> String {
            String(localized: "settings.bin.items \(count)")
        }
        static let emptyBinNow = String(localized: "settings.empty.bin.now")

        // General - About section
        static let sectionAbout = String(localized: "settings.section.about")
        static let fieldVersion = String(localized: "settings.field.version")
        static let fieldBuild = String(localized: "settings.field.build")

        // General - Language section
        static let sectionLanguage = String(localized: "settings.section.language")
        static let fieldCurrent = String(localized: "settings.field.current")
        static let systemDefault = String(localized: "settings.system.default")
        static let searchLanguages = String(localized: "settings.search.languages")
        static let usingSystemLanguage = String(localized: "settings.using.system.language")
        static let restartRequired = String(localized: "settings.restart.required")

        // Tools - CLI section
        static let sectionCli = String(localized: "settings.section.cli")
        static let cliTitle = String(localized: "settings.cli.title")
        static let cliDescription = String(localized: "settings.cli.description")
        static let cliPath = String(localized: "settings.cli.path")
        static let cliInstall = String(localized: "settings.cli.install")
        static let cliUninstall = String(localized: "settings.cli.uninstall")
        static let cliInstalled = String(localized: "settings.cli.installed")
        static let cliNotInstalled = String(localized: "settings.cli.not.installed")
        static let cliUsage = String(localized: "settings.cli.usage")
        static let cliLocation = String(localized: "settings.cli.location")
        static let enableTerminalAutorun = String(localized: "settings.enable.terminal.autorun")
        static let enableTerminalAutorunHelp = String(localized: "settings.enable.terminal.autorun.help")

        // Tools - MCP section
        static let sectionMcp = String(localized: "settings.section.mcp")
        static let mcpTitle = String(localized: "settings.mcp.title")
        static let mcpDescription = String(localized: "settings.mcp.description")
        static let mcpLocation = String(localized: "settings.mcp.location")
        static let mcpClaudeConfig = String(localized: "settings.mcp.claude.config")
        static let mcpLocalOnly = String(localized: "settings.mcp.local.only")
        static let mcpInstallDescription = String(localized: "settings.mcp.install.description")
        static let configCopied = String(localized: "settings.config.copied")
        static let copyConfig = String(localized: "settings.copy.config")

        // Tools - Agents section
        static let sectionAgents = String(localized: "settings.section.agents")
    }

    // MARK: - Command Palette
    enum Palette {
        static let placeholder = String(localized: "palette.placeholder")
        static let noResults = String(localized: "palette.no.results")
    }

    // MARK: - Help View
    enum Help {
        static let title = String(localized: "help.title")
        static let searchPlaceholder = String(localized: "help.search.placeholder")
    }

    // MARK: - Alerts
    enum Alert {
        static let error = String(localized: "alert.error")
        static let success = String(localized: "alert.success")
    }
}
