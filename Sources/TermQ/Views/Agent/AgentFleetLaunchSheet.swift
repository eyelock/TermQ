import SwiftUI
import TermQCore

/// Sheet for launching a fleet of parallel agent sessions against the same task.
///
/// Creates `sessionCount` cards that share a `fleetId`, each with a distinct
/// worktree path under `baseWorktreeDir`. The loop driver command is built from
/// `driverBase` + harness + task + worktree per session.
struct AgentFleetLaunchSheet: View {
    @ObservedObject var boardViewModel: BoardViewModel
    let onDismiss: () -> Void

    @AppStorage("agent.loopDriverCommand") private var globalDriverCommand: String = ""

    @State private var harnessId: String = ""
    @State private var task: String = ""
    @State private var sessionCount: Int = 3
    @State private var baseWorktreeDir: String = ""

    private let countOptions = [2, 3, 4, 5]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(width: 480)
        .onAppear {
            if baseWorktreeDir.isEmpty, let home = ProcessInfo.processInfo.environment["HOME"] {
                baseWorktreeDir = "\(home)/fleet-runs"
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "square.stack.3d.up")
                .foregroundColor(.accentColor)
            Text(Strings.Fleet.launchTitle)
                .font(.headline)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var form: some View {
        Form {
            Section {
                LabeledContent(Strings.Fleet.fieldHarness) {
                    TextField(Strings.Fleet.fieldHarnessPlaceholder, text: $harnessId)
                        .textFieldStyle(.plain)
                }

                LabeledContent(Strings.Fleet.fieldSessions) {
                    Picker("", selection: $sessionCount) {
                        ForEach(countOptions, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                }

                LabeledContent(Strings.Fleet.fieldBaseWorktree) {
                    TextField(Strings.Fleet.fieldBaseWorktreePlaceholder, text: $baseWorktreeDir)
                        .textFieldStyle(.plain)
                }
            } header: {
                Text(Strings.Fleet.sectionConfig)
            }

            Section {
                TextEditor(text: $task)
                    .font(.body)
                    .frame(minHeight: 100)
                    .overlay(alignment: .topLeading) {
                        if task.isEmpty {
                            Text(Strings.Fleet.taskPlaceholder)
                                .foregroundStyle(.secondary)
                                .allowsHitTesting(false)
                                .padding(.top, 4)
                                .padding(.leading, 4)
                        }
                    }
            } header: {
                Text(Strings.Fleet.sectionTask)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(Strings.Fleet.cancel) {
                onDismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button(Strings.Fleet.launch) {
                launch()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canLaunch)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var canLaunch: Bool {
        !harnessId.trimmingCharacters(in: .whitespaces).isEmpty
            && !task.trimmingCharacters(in: .whitespaces).isEmpty
            && !baseWorktreeDir.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func launch() {
        let base = globalDriverCommand.trimmingCharacters(in: .whitespaces)
        let driver = base.isEmpty ? "ynh agent run" : base
        boardViewModel.createFleet(
            harnessId: harnessId.trimmingCharacters(in: .whitespaces),
            task: task.trimmingCharacters(in: .whitespaces),
            count: sessionCount,
            baseWorktreeDir: baseWorktreeDir.trimmingCharacters(in: .whitespaces),
            driverBase: driver
        )
        onDismiss()
    }
}
