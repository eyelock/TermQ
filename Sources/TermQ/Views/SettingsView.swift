import SwiftUI

struct SettingsView: View {
    @State private var selectedLocation: InstallLocation = .usrLocalBin
    @State private var installedLocation: InstallLocation?
    @State private var isInstalling = false
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var alertIsError = false

    // Terminal preferences
    @AppStorage("copyOnSelect") private var copyOnSelect = false

    var body: some View {
        Form {
            Section {
                Toggle("Copy on select", isOn: $copyOnSelect)
                    .help("Automatically copy selected text to clipboard")
            } header: {
                Text("Terminal")
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "terminal")
                            .font(.title2)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Command Line Tool")
                                .font(.headline)
                            Text("termq - Open terminals from the command line")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if installedLocation != nil {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Installed")
                                    .foregroundColor(.green)
                            }
                            .font(.caption)
                        }
                    }

                    Divider()

                    if let location = installedLocation {
                        // Already installed
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Location:")
                                    .foregroundColor(.secondary)
                                Text(location.fullPath)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .font(.caption)

                            Text("Usage: termq open [--name \"My Terminal\"] [--column \"In Progress\"]")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)

                            HStack {
                                Button("Reinstall") {
                                    installCLI()
                                }
                                .disabled(isInstalling)

                                Button("Uninstall", role: .destructive) {
                                    uninstallCLI()
                                }
                                .disabled(isInstalling)
                            }
                        }
                    } else {
                        // Not installed - show install options
                        VStack(alignment: .leading, spacing: 12) {
                            Text("The CLI tool allows you to open new terminals in TermQ from any terminal window.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Picker("Install to:", selection: $selectedLocation) {
                                ForEach(InstallLocation.allCases) { location in
                                    Text(location.displayName).tag(location)
                                }
                            }
                            .pickerStyle(.radioGroup)

                            Text(selectedLocation.pathNote)
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Button {
                                installCLI()
                            } label: {
                                HStack {
                                    if isInstalling {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    Text(isInstalling ? "Installing..." : "Install Command Line Tool")
                                }
                            }
                            .disabled(isInstalling)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("CLI Tools")
            }

            Section {
                LabeledContent(
                    "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 380)
        .alert(alertIsError ? "Error" : "Success", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage ?? "")
        }
        .onAppear {
            refreshInstallStatus()
        }
    }

    private func refreshInstallStatus() {
        installedLocation = CLIInstaller.currentInstallLocation
    }

    private func installCLI() {
        isInstalling = true
        let location = installedLocation ?? selectedLocation
        Task {
            let result = await CLIInstaller.install(to: location)
            await MainActor.run {
                isInstalling = false
                switch result {
                case .success(let message):
                    alertMessage = message
                    alertIsError = false
                    showAlert = true
                    refreshInstallStatus()
                case .failure(let error):
                    if case .userCancelled = error {
                        return
                    }
                    alertMessage = error.localizedDescription
                    alertIsError = true
                    showAlert = true
                }
            }
        }
    }

    private func uninstallCLI() {
        guard let location = installedLocation else { return }
        isInstalling = true
        Task {
            let result = await CLIInstaller.uninstall(from: location)
            await MainActor.run {
                isInstalling = false
                switch result {
                case .success(let message):
                    alertMessage = message
                    alertIsError = false
                    showAlert = true
                    refreshInstallStatus()
                case .failure(let error):
                    if case .userCancelled = error {
                        return
                    }
                    alertMessage = error.localizedDescription
                    alertIsError = true
                    showAlert = true
                }
            }
        }
    }
}
