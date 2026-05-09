import SwiftUI

struct SettingsGitHubView: View {
    @Binding var remotePRFeedCap: Int

    var body: some View {
        Section {
            Stepper(
                value: $remotePRFeedCap,
                in: 5...100,
                step: 5
            ) {
                HStack {
                    Text(Strings.Settings.githubFeedCapLabel)
                    Spacer()
                    Text("\(remotePRFeedCap)")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            Text(Strings.Settings.githubFeedCapHelp)
                .font(.caption)
                .foregroundColor(.secondary)
        } header: {
            Text(Strings.Settings.githubSectionFeed)
        }
    }
}
