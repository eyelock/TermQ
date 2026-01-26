import Foundation
import SwiftUI

/// Resource bundle containing all localizations
private let resourceBundle: Bundle = {
    // Check Contents/Resources first (for signed app), then Bundle.module
    if let resourcesPath = Bundle.main.resourceURL?.appendingPathComponent("TermQ_TermQ.bundle").path,
        let bundle = Bundle(path: resourcesPath)
    {
        return bundle
    }
    return Bundle.module
}()

/// Parse a .strings file into a dictionary, handling comments
private func parseStringsFile(at url: URL) -> [String: String]? {
    guard let content = try? String(contentsOf: url, encoding: .utf8) else {
        return nil
    }

    var result: [String: String] = [:]

    // Remove block comments
    var cleanContent = content
    while let startRange = cleanContent.range(of: "/*"),
        let endRange = cleanContent.range(of: "*/", range: startRange.upperBound..<cleanContent.endIndex)
    {
        cleanContent.removeSubrange(startRange.lowerBound...endRange.upperBound)
    }

    for line in cleanContent.components(separatedBy: .newlines) {
        var line = line

        // Remove line comments
        if let commentRange = line.range(of: "//") {
            line = String(line[..<commentRange.lowerBound])
        }

        line = line.trimmingCharacters(in: .whitespaces)

        // Skip empty lines
        guard !line.isEmpty, line.hasPrefix("\"") else { continue }

        // Parse "key" = "value"; using regex-like approach
        // Find first quoted string (key)
        guard let keyStart = line.firstIndex(of: "\"") else { continue }
        let afterKeyStart = line.index(after: keyStart)
        guard afterKeyStart < line.endIndex,
            let keyEnd = line[afterKeyStart...].firstIndex(of: "\"")
        else { continue }

        let key = String(line[afterKeyStart..<keyEnd])

        // Find "=" and value
        let afterKey = line.index(after: keyEnd)
        guard afterKey < line.endIndex,
            let equalsRange = line[afterKey...].range(of: "="),
            let valueStart = line[equalsRange.upperBound...].firstIndex(of: "\"")
        else { continue }

        // Find end of value (handle escaped quotes)
        let afterValueStart = line.index(after: valueStart)
        guard afterValueStart < line.endIndex else { continue }

        var valueEnd: String.Index?
        var idx = afterValueStart
        while idx < line.endIndex {
            if line[idx] == "\"" {
                // Check if escaped
                let prevIdx = line.index(before: idx)
                if prevIdx >= afterValueStart && line[prevIdx] == "\\" {
                    idx = line.index(after: idx)
                    continue
                }
                valueEnd = idx
                break
            }
            idx = line.index(after: idx)
        }

        guard let valueEnd = valueEnd else { continue }
        var value = String(line[afterValueStart..<valueEnd])

        // Unescape common sequences
        value = value.replacingOccurrences(of: "\\\"", with: "\"")
        value = value.replacingOccurrences(of: "\\n", with: "\n")
        value = value.replacingOccurrences(of: "\\\\", with: "\\")

        result[key] = value
    }

    return result.isEmpty ? nil : result
}

/// Manually loaded strings dictionary for user's preferred language
/// We parse .strings files directly because Bundle(path:) on .lproj folders
/// doesn't work with localizedString() - it needs a proper bundle structure
private let userStringsCache: [String: String]? = {
    let preferredLanguage = UserDefaults.standard.string(forKey: "preferredLanguage") ?? ""

    // If no preference, return nil to use bundle's system language support
    guard !preferredLanguage.isEmpty else {
        return nil
    }

    // Try exact match first, then base language code
    let languageCodes = [preferredLanguage, preferredLanguage.components(separatedBy: "-").first ?? preferredLanguage]

    for code in languageCodes {
        if let lprojPath = resourceBundle.path(forResource: code, ofType: "lproj") {
            let stringsURL = URL(fileURLWithPath: lprojPath).appendingPathComponent("Localizable.strings")
            if let dict = parseStringsFile(at: stringsURL) {
                return dict
            }
        }
    }

    return nil
}()

/// Helper to get localized string
private func localized(_ key: String) -> String {
    // Use manually loaded strings if user has a preferred language
    if let cache = userStringsCache, let value = cache[key] {
        return value
    }
    // Fall back to bundle's localization (uses system language)
    return resourceBundle.localizedString(forKey: key, value: nil, table: "Localizable")
}

/// Helper for strings with arguments
private func localized(_ key: String, _ args: CVarArg...) -> String {
    let format: String
    if let cache = userStringsCache, let value = cache[key] {
        format = value
    } else {
        format = resourceBundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }
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
        static var enabled: String { localized("common.enabled") }
        static var disabled: String { localized("common.disabled") }
        static var browse: String { localized("common.browse") }
        static var select: String { localized("common.select") }
        static var apply: String { localized("common.apply") }
        static var preview: String { localized("common.preview") }
        static var quit: String { localized("common.quit") }
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
        static var duplicate: String { localized("card.duplicate") }
        static var wired: String { localized("card.wired") }
        static var wiredHelp: String { localized("card.wired.help") }
        static var needsAttention: String { localized("card.needs.attention") }
        static var processing: String { localized("card.processing") }
        static var live: String { localized("card.live") }
        static var liveHelp: String { localized("card.live.help") }
        static var closeSession: String { localized("card.close.session") }
        static var killSession: String { localized("card.kill.session") }
        static var restartSession: String { localized("card.restart.session") }
        static var killTerminal: String { localized("card.kill.terminal") }
        static var killTerminalHelp: String { localized("card.kill.terminal.help") }
        static var tmux: String { localized("card.tmux") }
        static var tmuxHelp: String { localized("card.tmux.help") }
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
        static var checkForUpdates: String { localized("menu.check.for.updates") }
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
        // Security section
        static var sectionSecurity: String { localized("editor.section.security") }
        static var fieldSafePaste: String { localized("editor.field.safe.paste") }
        static var fieldSafePasteHelp: String { localized("editor.field.safe.paste.help") }
        static var fieldAllowAutorun: String { localized("editor.field.allow.autorun") }
        static var fieldAllowAutorunHelp: String { localized("editor.field.allow.autorun.help") }
        static var fieldAutorunDisabledGlobally: String { localized("editor.field.autorun.disabled.globally") }
        static var fieldAutorunEnableHint: String { localized("editor.field.autorun.enable.hint") }
        static var allowAgentPrompts: String { localized("editor.allow.agent.prompts") }
        static var allowAgentPromptsHelp: String { localized("editor.allow.agent.prompts.help") }
        static var allowAgentPromptsDisabledGlobally: String {
            localized("editor.allow.agent.prompts.disabled.globally")
        }
        static var allowOscClipboard: String { localized("editor.allow.osc.clipboard") }
        static var allowOscClipboardHelp: String { localized("editor.allow.osc.clipboard.help") }
        static var allowOscClipboardDisabledGlobally: String {
            localized("editor.allow.osc.clipboard.disabled.globally")
        }
        static var confirmExternalModifications: String { localized("editor.confirm.external.modifications") }
        static var confirmExternalModificationsHelp: String { localized("editor.confirm.external.modifications.help") }
        static var confirmExternalModificationsDisabledGlobally: String {
            localized("editor.confirm.external.modifications.disabled.globally")
        }
        static var disabledGlobally: String { localized("editor.disabled.globally") }

        // Tags section
        static var sectionTags: String { localized("editor.section.tags") }
        static var sectionAddTag: String { localized("editor.section.add.tag") }
        static var fieldTags: String { localized("editor.field.tags") }
        static var tagAdd: String { localized("editor.tag.add") }
        static var tagKeyPlaceholder: String { localized("editor.tag.key.placeholder") }
        static var tagValuePlaceholder: String { localized("editor.tag.value.placeholder") }
        static var tagsHelp: String { localized("editor.tags.help") }
        static var noTags: String { localized("editor.no.tags") }

        // Agent Configuration section
        static var sectionAgent: String { localized("editor.section.agent") }
        static var sectionPrompts: String { localized("editor.section.prompts") }
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
        static var interactiveModeToggle: String { localized("editor.interactive.mode.toggle") }
        static var interactiveModeHelp: String { localized("editor.interactive.mode.help") }
        static var nonInteractiveModeNote: String { localized("editor.non.interactive.mode.note") }

        static var cancel: String { localized("editor.cancel") }
        static var save: String { localized("editor.save") }
        static var saveOpen: String { localized("editor.save.open") }

        // Backend section
        static var sectionBackend: String { localized("editor.section.backend") }
        static var fieldBackend: String { localized("editor.field.backend") }
        static var tmuxPersistNote: String { localized("editor.tmux.persist.note") }
        static var backendRestartHint: String { localized("editor.backend.restart.hint") }

        // Environment section
        enum Environment {
            static var description: String { localized("editor.environment.description") }
            static var sectionTerminal: String { localized("editor.environment.section.terminal") }
            static var sectionAddVariable: String { localized("editor.environment.section.add.variable") }
            static var noVariables: String { localized("editor.environment.no.variables") }
            static var sectionInherited: String { localized("editor.environment.section.inherited") }
            static var noGlobalVariables: String { localized("editor.environment.no.global.variables") }
            static var editGlobal: String { localized("editor.environment.edit.global") }
            static var overrides: String { localized("editor.environment.overrides") }
            static var overridden: String { localized("editor.environment.overridden") }
            static var global: String { localized("editor.environment.global") }
            static var secretWarning: String { localized("editor.environment.secret.warning") }
        }
    }

    // MARK: - Security
    enum Security {
        static var externalModificationTitle: String { localized("security.external.modification.title") }
        static var externalModificationMessage: String { localized("security.external.modification.message") }
        static var allow: String { localized("security.allow") }
        static var deny: String { localized("security.deny") }
        static var allowAndDisablePrompt: String { localized("security.allow.disable.prompt") }
        static var oscClipboardEnabled: String { localized("security.osc.clipboard.enabled") }
        static var oscClipboardDisabled: String { localized("security.osc.clipboard.disabled") }
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
        static var tabDataAndSecurity: String { localized("settings.tab.data.and.security") }

        // General - Terminal section
        static var sectionTerminal: String { localized("settings.section.terminal") }
        static var fieldTheme: String { localized("settings.field.theme") }
        static var fieldThemeHelp: String { localized("settings.field.theme.help") }
        static var fieldCopyOnSelect: String { localized("settings.field.copy.on.select") }
        static var fieldCopyOnSelectHelp: String { localized("settings.field.copy.on.select.help") }
        static var fieldDefaultWorkingDirectory: String { localized("settings.field.default.working.directory") }
        static var fieldDefaultWorkingDirectoryHelp: String {
            localized("settings.field.default.working.directory.help")
        }
        static var fieldDefaultBackend: String { localized("settings.field.default.backend") }
        static var fieldDefaultBackendHelp: String { localized("settings.field.default.backend.help") }

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

        // General - Updates section
        static var sectionUpdates: String { localized("settings.section.updates") }
        static var checkForUpdates: String { localized("settings.check.for.updates") }
        static var autoCheckUpdates: String { localized("settings.auto.check.updates") }
        static var autoCheckUpdatesHelp: String { localized("settings.auto.check.updates.help") }
        static var includeBetaReleases: String { localized("settings.include.beta.releases") }
        static var includeBetaReleasesHelp: String { localized("settings.include.beta.releases.help") }

        // General - Data Directory section
        static var sectionDataDirectory: String { localized("settings.section.data.directory") }
        static var dataDirectory: String { localized("settings.data.directory") }
        static var dataDirectoryHelp: String { localized("settings.data.directory.help") }

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
        static var mcpInstall: String { localized("settings.mcp.install") }
        static var configCopied: String { localized("settings.config.copied") }
        static var copyConfig: String { localized("settings.copy.config") }

        // Tools - Agents section
        static var sectionAgents: String { localized("settings.section.agents") }

        // Tools - Status section
        static var sectionStatus: String { localized("settings.section.status") }
        static var statusReady: String { localized("settings.status.ready") }
        static var statusEnabled: String { localized("settings.status.enabled") }
        static var statusDisabled: String { localized("settings.status.disabled") }
        static var notInstalled: String { localized("settings.not.installed") }

        // Tools - tmux section
        static var sectionTmux: String { localized("settings.section.tmux") }
        static var tmuxDescription: String { localized("settings.tmux.description") }
        static var tmuxEnabled: String { localized("settings.tmux.enabled") }
        static var tmuxEnabledHelp: String { localized("settings.tmux.enabled.help") }
        static var tmuxVersion: String { localized("settings.tmux.version") }
        static var tmuxPath: String { localized("settings.tmux.path") }
        static var tmuxInfo: String { localized("settings.tmux.info") }
        static var tmuxNotInstalledDescription: String { localized("settings.tmux.not.installed.description") }
        static var tmuxInstallHint: String { localized("settings.tmux.install.hint") }
        static var tmuxCheckAgain: String { localized("settings.tmux.check.again") }
        static var copyToClipboard: String { localized("settings.copy.to.clipboard") }

        // tmux Status section
        static var sectionTmuxStatus: String { localized("settings.section.tmux.status") }
        static var tmuxStatusReady: String { localized("settings.tmux.status.ready") }
        static var tmuxStatusDisabled: String { localized("settings.tmux.status.disabled") }
        static func tmuxActiveSessions(_ count: Int) -> String {
            localized("settings.tmux.active.sessions %lld", count)
        }
        static var tmuxEnableHint: String { localized("settings.tmux.enable.hint") }
        static var tmuxEnableButton: String { localized("settings.tmux.enable.button") }
        static var tmuxAutoReattach: String { localized("settings.tmux.auto.reattach") }
        static var tmuxAutoReattachHelp: String { localized("settings.tmux.auto.reattach.help") }

        // Environment tab
        static var tabEnvironment: String { localized("settings.tab.environment") }

        // Environment section
        enum Environment {
            static var sectionConfiguration: String { localized("settings.environment.section.configuration") }
            static var configDirectory: String { localized("settings.environment.config.directory") }
            static var configDirectoryHelp: String { localized("settings.environment.config.directory.help") }
            static var resetDefault: String { localized("settings.environment.reset.default") }
            static var browseMessage: String { localized("settings.environment.browse.message") }

            static var sectionVariables: String { localized("settings.environment.section.variables") }
            static var sectionAddVariable: String { localized("settings.environment.section.add.variable") }
            static var noVariables: String { localized("settings.environment.no.variables") }
            static var keyPlaceholder: String { localized("settings.environment.key.placeholder") }
            static var valuePlaceholder: String { localized("settings.environment.value.placeholder") }
            static var secretPlaceholder: String { localized("settings.environment.secret.placeholder") }
            static var secret: String { localized("settings.environment.secret") }
            static var toggleVisibility: String { localized("settings.environment.toggle.visibility") }
            static var secretIndicator: String { localized("settings.environment.secret.indicator") }
            static var invalidKeyError: String { localized("settings.environment.invalid.key.error") }
            static var duplicateKeyError: String { localized("settings.environment.duplicate.key.error") }
            static var reservedKeyWarning: String { localized("settings.environment.reserved.key.warning") }

            static var sectionSecurity: String { localized("settings.environment.section.security") }
            static var encryptionStatus: String { localized("settings.environment.encryption.status") }
            static var encryptionActive: String { localized("settings.environment.encryption.active") }
            static var encryptionInactive: String { localized("settings.environment.encryption.inactive") }
            static var resetEncryptionKey: String { localized("settings.environment.reset.encryption.key") }
            static var resetEncryptionKeyWarning: String {
                localized("settings.environment.reset.encryption.key.warning")
            }
            static var resetConfirmTitle: String { localized("settings.environment.reset.confirm.title") }
            static var resetConfirmMessage: String { localized("settings.environment.reset.confirm.message") }
            static var resetConfirmButton: String { localized("settings.environment.reset.confirm.button") }
            static func resetConfirmMessageWithSecrets(global: Int, terminal: Int) -> String {
                let total = global + terminal
                let globalPart = global > 0 ? "\(global) global secret\(global == 1 ? "" : "s")" : nil
                let terminalPart = terminal > 0 ? "\(terminal) terminal secret\(terminal == 1 ? "" : "s")" : nil

                let parts = [globalPart, terminalPart].compactMap { $0 }
                let secretsList = parts.joined(separator: " and ")

                return
                    "This will permanently delete \(secretsList) (\(total) total). These secrets will be unrecoverable after the encryption key is reset.\n\n\(resetConfirmMessage)"
            }

            static var troubleshooting: String { localized("settings.environment.troubleshooting") }
            static var troubleshootingIntro: String { localized("settings.environment.troubleshooting.intro") }
            static var troubleshootingStep1: String { localized("settings.environment.troubleshooting.step1") }
            static var troubleshootingStep2: String { localized("settings.environment.troubleshooting.step2") }
            static var troubleshootingStep3: String { localized("settings.environment.troubleshooting.step3") }
            static var troubleshootingStep4: String { localized("settings.environment.troubleshooting.step4") }
            static var troubleshootingStep5: String { localized("settings.environment.troubleshooting.step5") }
        }

        // Security section
        static var sectionSecurity: String { localized("settings.section.security") }
        static var allowOscClipboard: String { localized("settings.allow.osc.clipboard") }
        static var allowOscClipboardHelp: String { localized("settings.allow.osc.clipboard.help") }
        static var confirmExternalModifications: String { localized("settings.confirm.external.modifications") }
        static var confirmExternalModificationsHelp: String {
            localized("settings.confirm.external.modifications.help")
        }
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
        static var quitWithDirectSessions: String { localized("alert.quit.direct.sessions") }
        static func quitWithDirectSessionsMessage(_ count: Int) -> String {
            localized("alert.quit.direct.sessions.message.simple %lld", count)
        }
        static func quitWithDirectSessionsMessageWithTmux(_ count: Int) -> String {
            localized("alert.quit.direct.sessions.message %lld", count)
        }
    }

    // MARK: - Backup
    enum Backup {
        static var title: String { localized("backup.title") }
        static var description: String { localized("backup.description") }
        static var exists: String { localized("backup.exists") }
        static var locationLabel: String { localized("backup.location.label") }
        static var locationPlaceholder: String { localized("backup.location.placeholder") }
        static var locationHelp: String { localized("backup.location.help") }
        static var frequencyLabel: String { localized("backup.frequency.label") }
        static var frequencyPicker: String { localized("backup.frequency.picker") }
        static var last: String { localized("backup.last") }
        static var ago: String { localized("backup.ago") }
        static var location: String { localized("backup.location") }
        static var backingUp: String { localized("backup.backing.up") }
        static var now: String { localized("backup.now") }
        static var restore: String { localized("backup.restore") }
        static var sectionHeader: String { localized("backup.section.header") }
        static var select: String { localized("backup.select") }
        static var chooseLocation: String { localized("backup.choose.location") }
        static var restartNotice: String { localized("backup.restart.notice") }
    }

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
