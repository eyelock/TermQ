import Foundation
import SwiftUI

/// Bundle for localized resources
private let localizedBundle: Bundle = {
    // Get the resource bundle - check Contents/Resources first (for signed app), then Bundle.module
    let resourceBundle: Bundle = {
        if let resourcesPath = Bundle.main.resourceURL?.appendingPathComponent("TermQ_TermQ.bundle").path,
            let bundle = Bundle(path: resourcesPath)
        {
            return bundle
        }
        return Bundle.module
    }()

    // Get the user's preferred language
    let preferredLanguage = UserDefaults.standard.string(forKey: "preferredLanguage") ?? ""

    // If no preference or empty, use the resource bundle (system language)
    guard !preferredLanguage.isEmpty else {
        return resourceBundle
    }

    // Find the .lproj folder for the selected language
    // Try exact match first, then base language code
    let languageCodes = [preferredLanguage, preferredLanguage.components(separatedBy: "-").first ?? preferredLanguage]

    for code in languageCodes {
        if let path = resourceBundle.path(forResource: code, ofType: "lproj"),
            let bundle = Bundle(path: path)
        {
            return bundle
        }
    }

    // Fall back to resource bundle
    return resourceBundle
}()

/// Helper to get localized string from the user's preferred language bundle
private func localized(_ key: String) -> String {
    localizedBundle.localizedString(forKey: key, value: nil, table: "Localizable")
}

/// Helper for strings with arguments
private func localized(_ key: String, _ args: CVarArg...) -> String {
    let format = localizedBundle.localizedString(forKey: key, value: nil, table: "Localizable")
    return String(format: format, arguments: args)
}

/// Centralized string localization for TermQ
/// Usage: Text(Strings.Board.columnOptions)
enum Strings {
    // MARK: - App
    static var appName: String { localized("app.name") }

    // MARK: - Common
    enum Common {
        static var ok: String { localized("common.ok") }
        static var cancel: String { localized("common.cancel") }
        static var save: String { localized("common.save") }
        static var delete: String { localized("common.delete") }
        static var edit: String { localized("common.edit") }
        static var close: String { localized("common.close") }
        static var add: String { localized("common.add") }
        static var reinstall: String { localized("common.reinstall") }
        static var uninstall: String { localized("common.uninstall") }
        static var installed: String { localized("common.installed") }
        static var browse: String { localized("common.browse") }
        static var apply: String { localized("common.apply") }
        static var preview: String { localized("common.preview") }
    }

    // MARK: - Board View
    enum Board {
        static var columnOptions: String { localized("board.column.options") }
        static var columnRename: String { localized("board.column.rename") }
        static var columnDelete: String { localized("board.column.delete") }
        static var columnDeleteDisabled: String { localized("board.column.delete.disabled") }
        static var addTerminal: String { localized("board.column.add.terminal") }
        static var addTerminalHelp: String { localized("board.column.add.terminal.help") }
        static var editColumn: String { localized("board.column.edit") }
    }

    // MARK: - Terminal Card
    enum Card {
        static var pin: String { localized("card.pin") }
        static var unpin: String { localized("card.unpin") }
        static var running: String { localized("card.running") }
        static var open: String { localized("card.open") }
        static var edit: String { localized("card.edit") }
        static var delete: String { localized("card.delete") }
        static var wired: String { localized("card.wired") }
        static var wiredHelp: String { localized("card.wired.help") }
        static var needsAttention: String { localized("card.needs.attention") }
        static var processing: String { localized("card.processing") }
        static var live: String { localized("card.live") }
        static var liveHelp: String { localized("card.live.help") }
        static var closeSession: String { localized("card.close.session") }
        static var restartSession: String { localized("card.restart.session") }
        static var killTerminal: String { localized("card.kill.terminal") }
        static var killTerminalHelp: String { localized("card.kill.terminal.help") }
    }

    // MARK: - Expanded Terminal View
    enum Terminal {
        static var ended: String { localized("terminal.ended") }
        static var restart: String { localized("terminal.restart") }
        static var restartHelp: String { localized("terminal.restart.help") }
        static var current: String { localized("terminal.current") }
        static var editHelp: String { localized("terminal.edit.help") }
        static var closeTabHelp: String { localized("terminal.close.tab.help") }
        static var newTabHelp: String { localized("terminal.new.tab.help") }
        static func switchTo(_ name: String) -> String {
            localized("terminal.switch.to %@", name)
        }
        static func tabHelp(_ title: String, _ column: String) -> String {
            localized("terminal.tab.help %@ %@", title, column)
        }
    }

    // MARK: - Toolbar
    enum Toolbar {
        static var back: String { localized("toolbar.back") }
        static var backHelp: String { localized("toolbar.back.help") }
        static var moveTo: String { localized("toolbar.move.to") }
        static var newQuick: String { localized("toolbar.new.quick") }
        static var newQuickHelp: String { localized("toolbar.new.quick.help") }
        static var edit: String { localized("toolbar.edit") }
        static var editHelp: String { localized("toolbar.edit.help") }
        static var pin: String { localized("toolbar.pin") }
        static var pinHelp: String { localized("toolbar.pin.help") }
        static var unpin: String { localized("toolbar.unpin") }
        static var unpinHelp: String { localized("toolbar.unpin.help") }
        static var delete: String { localized("toolbar.delete") }
        static var deleteHelp: String { localized("toolbar.delete.help") }
        static var add: String { localized("toolbar.add") }
        static var addHelp: String { localized("toolbar.add.help") }
        static var openTerminalApp: String { localized("toolbar.open.terminal.app") }
        static var openTerminalAppHelp: String { localized("toolbar.open.terminal.app.help") }
        static var newTerminal: String { localized("toolbar.new.terminal") }
        static var newColumn: String { localized("toolbar.new.column") }
        static func binCount(_ count: Int) -> String {
            localized("toolbar.bin.count %lld", count)
        }
    }

    // MARK: - Menu Commands
    enum Menu {
        static var help: String { localized("menu.help") }
        static var newTerminalQuick: String { localized("menu.new.terminal.quick") }
        static var newTerminal: String { localized("menu.new.terminal") }
        static var newTerminalDialog: String { localized("menu.new.terminal.dialog") }
        static var newColumn: String { localized("menu.new.column") }
        static var back: String { localized("menu.back") }
        static var togglePin: String { localized("menu.toggle.pin") }
        static var nextPinned: String { localized("menu.next.pinned") }
        static var previousPinned: String { localized("menu.previous.pinned") }
    }

    // MARK: - Command Palette
    enum CommandPalette {
        static var newTerminal: String { localized("command.palette.new.terminal") }
        static var newColumn: String { localized("command.palette.new.column") }
        static var toggleZoom: String { localized("command.palette.toggle.zoom") }
        static var findInTerminal: String { localized("command.palette.find") }
        static var exportSession: String { localized("command.palette.export") }
        static var backToBoard: String { localized("command.palette.back") }
        static var openInTerminalApp: String { localized("command.palette.open.terminal.app") }
        static var toggleFavourite: String { localized("command.palette.toggle.favourite") }
    }

    // MARK: - Delete Confirmation
    enum Delete {
        static var title: String { localized("delete.title") }
        static var moveToBin: String { localized("delete.move.to.bin") }
        static func message(_ name: String) -> String {
            localized("delete.message %@", name)
        }
        static func binMessage(_ name: String) -> String {
            localized("delete.bin.message %@", name)
        }
        static var cancel: String { localized("delete.cancel") }
        static var confirm: String { localized("delete.confirm") }
        static var permanent: String { localized("delete.permanent") }
    }

    // MARK: - Card Editor
    enum Editor {
        static var titleNew: String { localized("editor.title.new") }
        static var titleEdit: String { localized("editor.title.edit") }
        static var tabGeneral: String { localized("editor.tab.general") }
        static var tabAdvanced: String { localized("editor.tab.advanced") }

        // General tab
        static var sectionDetails: String { localized("editor.section.details") }
        static var fieldName: String { localized("editor.field.name") }
        static var fieldNamePlaceholder: String { localized("editor.field.name.placeholder") }
        static var fieldDescription: String { localized("editor.field.description") }
        static var fieldDescriptionPlaceholder: String { localized("editor.field.description.placeholder") }
        static var fieldColumn: String { localized("editor.field.column") }
        static var fieldBadges: String { localized("editor.field.badges") }
        static var fieldBadgesPlaceholder: String { localized("editor.field.badges.placeholder") }
        static var fieldBadgesHelp: String { localized("editor.field.badges.help") }

        // Appearance section
        static var sectionAppearance: String { localized("editor.section.appearance") }
        static var fieldTheme: String { localized("editor.field.theme") }
        static var fieldThemeDefault: String { localized("editor.field.theme.default") }
        static var fieldFontSize: String { localized("editor.field.font.size") }
        static var fontPreview: String { localized("editor.font.preview") }

        // Terminal section
        static var sectionTerminal: String { localized("editor.section.terminal") }
        static var fieldDirectory: String { localized("editor.field.directory") }
        static var fieldDirectoryHelp: String { localized("editor.field.directory.help") }
        static var fieldShell: String { localized("editor.field.shell") }
        static var fieldShellHelp: String { localized("editor.field.shell.help") }

        // Automation section
        static var sectionAutomation: String { localized("editor.section.automation") }
        static var fieldInitCommand: String { localized("editor.field.init.command") }
        static var fieldInitCommandHelp: String { localized("editor.field.init.command.help") }
        static var fieldSafePaste: String { localized("editor.field.safe.paste") }
        static var fieldSafePasteHelp: String { localized("editor.field.safe.paste.help") }
        static var fieldAllowAutorun: String { localized("editor.field.allow.autorun") }
        static var fieldAllowAutorunHelp: String { localized("editor.field.allow.autorun.help") }
        static var fieldAutorunDisabledGlobally: String { localized("editor.field.autorun.disabled.globally") }
        static var fieldAutorunEnableHint: String { localized("editor.field.autorun.enable.hint") }

        // Tags section
        static var sectionTags: String { localized("editor.section.tags") }
        static var fieldTags: String { localized("editor.field.tags") }
        static var tagAdd: String { localized("editor.tag.add") }
        static var tagKeyPlaceholder: String { localized("editor.tag.key.placeholder") }
        static var tagValuePlaceholder: String { localized("editor.tag.value.placeholder") }
        static var tagsHelp: String { localized("editor.tags.help") }

        // Agent Configuration section
        static var sectionAgent: String { localized("editor.section.agent") }
        static var fieldTerminalAllowsAutorun: String { localized("editor.field.terminal.allows.autorun") }
        static var fieldPersistentContext: String { localized("editor.field.persistent.context") }
        static var fieldPersistentContextHelp: String { localized("editor.field.persistent.context.help") }
        static var fieldNextAction: String { localized("editor.field.next.action") }
        static var fieldNextActionHelp: String { localized("editor.field.next.action.help") }

        // Command Generator section
        static var sectionCommandGenerator: String { localized("editor.section.command.generator") }
        static var fieldApplyToInitCommand: String { localized("editor.field.apply.to.init.command") }
        static var fieldApplyToInitCommandHelp: String { localized("editor.field.apply.to.init.command.help") }
        static var noLlmPromptWarning: String { localized("editor.no.llm.prompt.warning") }
        static var nonInteractiveNote: String { localized("editor.non.interactive.note") }

        static var cancel: String { localized("editor.cancel") }
        static var save: String { localized("editor.save") }
        static var saveOpen: String { localized("editor.save.open") }
    }

    // MARK: - Column Editor
    enum ColumnEditor {
        static var titleNew: String { localized("column.editor.title.new") }
        static var titleEdit: String { localized("column.editor.title.edit") }
        static var fieldName: String { localized("column.editor.field.name") }
        static var fieldNamePlaceholder: String { localized("column.editor.field.name.placeholder") }
        static var fieldDescription: String { localized("column.editor.field.description") }
        static var fieldDescriptionPlaceholder: String { localized("column.editor.field.description.placeholder") }
        static var fieldColor: String { localized("column.editor.field.color") }
        static var cancel: String { localized("column.editor.cancel") }
        static var save: String { localized("column.editor.save") }
    }

    // MARK: - Bin
    enum Bin {
        static var title: String { localized("bin.title") }
        static var empty: String { localized("bin.empty") }
        static var emptyButton: String { localized("bin.empty.button") }
        static var closeHelp: String { localized("bin.close.help") }
        static var restoreHelp: String { localized("bin.restore.help") }
        static var deleteHelp: String { localized("bin.delete.help") }
        static func deleted(_ date: String) -> String {
            localized("bin.deleted %@", date)
        }
        static func daysRemaining(_ days: Int) -> String {
            localized("bin.days.remaining %lld", days)
        }
    }

    // MARK: - Settings
    enum Settings {
        static var title: String { localized("settings.title") }
        static var tabGeneral: String { localized("settings.tab.general") }
        static var tabTools: String { localized("settings.tab.tools") }

        // General - Terminal section
        static var sectionTerminal: String { localized("settings.section.terminal") }
        static var fieldTheme: String { localized("settings.field.theme") }
        static var fieldThemeHelp: String { localized("settings.field.theme.help") }
        static var fieldCopyOnSelect: String { localized("settings.field.copy.on.select") }
        static var fieldCopyOnSelectHelp: String { localized("settings.field.copy.on.select.help") }

        // General - Bin section
        static var sectionBin: String { localized("settings.section.bin") }
        static func autoEmpty(_ days: Int) -> String {
            localized("settings.auto.empty %lld", days)
        }
        static var autoEmptyHelp: String { localized("settings.auto.empty.help") }
        static var binEmpty: String { localized("settings.bin.empty") }
        static func binItems(_ count: Int) -> String {
            localized("settings.bin.items %lld", count)
        }
        static var emptyBinNow: String { localized("settings.empty.bin.now") }

        // General - About section
        static var sectionAbout: String { localized("settings.section.about") }
        static var fieldVersion: String { localized("settings.field.version") }
        static var fieldBuild: String { localized("settings.field.build") }

        // General - Language section
        static var sectionLanguage: String { localized("settings.section.language") }
        static var fieldCurrent: String { localized("settings.field.current") }
        static var systemDefault: String { localized("settings.system.default") }
        static var searchLanguages: String { localized("settings.search.languages") }
        static var usingSystemLanguage: String { localized("settings.using.system.language") }
        static var restartRequired: String { localized("settings.restart.required") }

        // Tools - CLI section
        static var sectionCli: String { localized("settings.section.cli") }
        static var cliTitle: String { localized("settings.cli.title") }
        static var cliDescription: String { localized("settings.cli.description") }
        static var cliPath: String { localized("settings.cli.path") }
        static var cliInstall: String { localized("settings.cli.install") }
        static var cliUninstall: String { localized("settings.cli.uninstall") }
        static var cliInstalled: String { localized("settings.cli.installed") }
        static var cliNotInstalled: String { localized("settings.cli.not.installed") }
        static var cliUsage: String { localized("settings.cli.usage") }
        static var cliLocation: String { localized("settings.cli.location") }
        static var enableTerminalAutorun: String { localized("settings.enable.terminal.autorun") }
        static var enableTerminalAutorunHelp: String { localized("settings.enable.terminal.autorun.help") }

        // Tools - MCP section
        static var sectionMcp: String { localized("settings.section.mcp") }
        static var mcpTitle: String { localized("settings.mcp.title") }
        static var mcpDescription: String { localized("settings.mcp.description") }
        static var mcpLocation: String { localized("settings.mcp.location") }
        static var mcpClaudeConfig: String { localized("settings.mcp.claude.config") }
        static var mcpLocalOnly: String { localized("settings.mcp.local.only") }
        static var mcpInstallDescription: String { localized("settings.mcp.install.description") }
        static var configCopied: String { localized("settings.config.copied") }
        static var copyConfig: String { localized("settings.copy.config") }

        // Tools - Agents section
        static var sectionAgents: String { localized("settings.section.agents") }
    }

    // MARK: - Command Palette
    enum Palette {
        static var placeholder: String { localized("palette.placeholder") }
        static var noResults: String { localized("palette.no.results") }
    }

    // MARK: - Help View
    enum Help {
        static var title: String { localized("help.title") }
        static var searchPlaceholder: String { localized("help.search.placeholder") }
    }

    // MARK: - Alerts
    enum Alert {
        static var error: String { localized("alert.error") }
        static var success: String { localized("alert.success") }
    }
}
