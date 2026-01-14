import AppKit
import SwiftUI

struct BackupSettingsView: View {
    @State private var backupLocation: String = BackupManager.backupLocation
    @State private var frequency: BackupFrequency = BackupManager.frequency
    @State private var isBackingUp = false
    @State private var isRestoring = false
    @State private var showLocationPicker = false
    @State private var showRestorePicker = false

    // Alert state
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var alertIsError = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Image(systemName: "externaldrive.badge.timemachine")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Backup")
                            .font(.headline)
                        Text("Protect your board data from accidental loss")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if BackupManager.hasBackup {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Backup exists")
                                .foregroundColor(.green)
                        }
                        .font(.caption)
                    }
                }

                Divider()

                // Backup location
                VStack(alignment: .leading, spacing: 4) {
                    Text("Backup Location")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        TextField("~/.termq", text: $backupLocation)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: backupLocation) { _, newValue in
                                BackupManager.backupLocation = newValue
                            }

                        Button("Browse...") {
                            browseForLocation()
                        }
                    }

                    Text("This location survives app uninstall (unlike ~/Library/Application Support)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Frequency picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Backup Frequency")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Frequency", selection: $frequency) {
                        ForEach(BackupFrequency.allCases) { freq in
                            VStack(alignment: .leading) {
                                Text(freq.displayName)
                            }
                            .tag(freq)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: frequency) { _, newValue in
                        BackupManager.frequency = newValue
                    }

                    Text(frequency.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Backup info and actions
                VStack(alignment: .leading, spacing: 8) {
                    let info = BackupManager.backupInfo
                    if info.exists, let date = info.date {
                        HStack {
                            Text("Last backup:")
                                .foregroundColor(.secondary)
                            Text(date, style: .relative)
                            Text("ago")
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)

                        HStack {
                            Text("Location:")
                                .foregroundColor(.secondary)
                            Text(BackupManager.backupFilePath)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .font(.caption)
                    }

                    HStack {
                        Button {
                            performBackup()
                        } label: {
                            HStack {
                                if isBackingUp {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(isBackingUp ? "Backing up..." : "Backup Now")
                            }
                        }
                        .disabled(isBackingUp || isRestoring)

                        Button("Restore from Backup...") {
                            showRestorePicker = true
                        }
                        .disabled(isBackingUp || isRestoring)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Data Protection")
        }
        .alert(alertIsError ? "Error" : "Success", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage ?? "")
        }
        .fileImporter(
            isPresented: $showRestorePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleRestoreFileSelection(result)
        }
    }

    // MARK: - Actions

    private func browseForLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose a backup location"

        if panel.runModal() == .OK, let url = panel.url {
            backupLocation = url.path
            BackupManager.backupLocation = url.path
        }
    }

    private func performBackup() {
        isBackingUp = true
        Task {
            // Small delay for UI feedback
            try? await Task.sleep(nanoseconds: 100_000_000)

            let result = BackupManager.backup()

            await MainActor.run {
                isBackingUp = false
                switch result {
                case .success(let message):
                    alertMessage = message
                    alertIsError = false
                    showAlert = true
                case .failure(let error):
                    alertMessage = error.localizedDescription
                    alertIsError = true
                    showAlert = true
                }
            }
        }
    }

    private func handleRestoreFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            performRestore(from: url)
        case .failure(let error):
            alertMessage = error.localizedDescription
            alertIsError = true
            showAlert = true
        }
    }

    private func performRestore(from url: URL) {
        isRestoring = true
        Task {
            // Small delay for UI feedback
            try? await Task.sleep(nanoseconds: 100_000_000)

            let result = BackupManager.restore(from: url)

            await MainActor.run {
                isRestoring = false
                switch result {
                case .success(let message):
                    alertMessage = "\(message)\n\nPlease restart TermQ to see your restored data."
                    alertIsError = false
                    showAlert = true
                case .failure(let error):
                    alertMessage = error.localizedDescription
                    alertIsError = true
                    showAlert = true
                }
            }
        }
    }
}
