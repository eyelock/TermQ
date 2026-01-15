import SwiftUI
import TermQCore

/// MCP server status indicator - shows if current terminal's LLM is aware of TermQ
struct MCPStatusView: View {
    let isWired: Bool

    private var isInstalled: Bool {
        MCPServerInstaller.currentInstallLocation != nil
    }

    var body: some View {
        Image(systemName: "cpu")
            .foregroundColor(
                isInstalled
                    ? (isWired ? .green : .secondary)
                    : .secondary.opacity(0.3)
            )
            .help(tooltip)
    }

    private var tooltip: String {
        if !isInstalled {
            return Strings.Settings.mcpInstallDescription
        } else if isWired {
            return Strings.Card.wiredHelp
        } else {
            return Strings.Settings.mcpDescription
        }
    }
}
