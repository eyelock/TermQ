import SwiftUI
import TermQShared

// MARK: - Agent Loop Section

extension ToolsTabContent {
    @ViewBuilder
    var agentSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(Strings.Settings.Agent.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(
                    Strings.Settings.Agent.enableAgentTab,
                    isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "feature.agentTab") },
                        set: { UserDefaults.standard.set($0, forKey: "feature.agentTab") }
                    )
                )
                .help(Strings.Settings.Agent.enableAgentTabHelp)
            }
            .padding(.vertical, 4)
        } header: {
            Text(Strings.Settings.Agent.sectionTitle)
        }
    }
}
