import SwiftUI

/// Multi-step wizard for complete TermQ uninstallation
struct UninstallView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep: UninstallStep = .overview
    @State private var removeCLI = true
    @State private var removeMCP = true
    @State private var removeAppData = false
    @State private var isProcessing = false
    @State private var completedSteps: [String] = []
    @State private var errorMessage: String?

    private enum UninstallStep {
        case overview
        case backup
        case confirmation
        case inProgress
        case complete
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Uninstall TermQ")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content based on current step
            Group {
                switch currentStep {
                case .overview:
                    overviewStep
                case .backup:
                    backupStep
                case .confirmation:
                    confirmationStep
                case .inProgress:
                    progressStep
                case .complete:
                    completeStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 450, height: 400)
    }

    // MARK: - Step Views

    @ViewBuilder
    private var overviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This will remove the following from your system:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $removeCLI) {
                    HStack {
                        Image(systemName: "terminal")
                        VStack(alignment: .leading) {
                            Text("CLI Tool")
                                .font(.body)
                            Text("/usr/local/bin/termq")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Toggle(isOn: $removeMCP) {
                    HStack {
                        Image(systemName: "server.rack")
                        VStack(alignment: .leading) {
                            Text("MCP Server")
                                .font(.body)
                            Text("/usr/local/bin/termqmcp")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Toggle(isOn: $removeAppData) {
                    HStack {
                        Image(systemName: "folder")
                        VStack(alignment: .leading) {
                            Text("App Data")
                                .font(.body)
                            Text("~/Library/Application Support/TermQ")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if removeAppData {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("A backup will be created before removing app data")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.leading, 24)
                }
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Continue") {
                    if removeAppData {
                        currentStep = .backup
                    } else {
                        currentStep = .confirmation
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!removeCLI && !removeMCP && !removeAppData)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var backupStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.timemachine")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("Creating Backup")
                .font(.headline)

            Text("Backing up your board data to:\n\(BackupManager.backupFilePath)")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)

            Spacer()
        }
        .padding()
        .onAppear {
            performBackup()
        }
    }

    @ViewBuilder
    private var confirmationStep: some View {
        VStack(spacing: 16) {
            if removeAppData {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)

                Text("Backup Complete")
                    .font(.headline)

                Text("Your data has been backed up to:\n\(BackupManager.backupFilePath)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Divider()
            }

            Text("Ready to remove:")
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 8) {
                if removeCLI {
                    Label("CLI Tool", systemImage: "checkmark")
                }
                if removeMCP {
                    Label("MCP Server", systemImage: "checkmark")
                }
                if removeAppData {
                    Label("App Data", systemImage: "checkmark")
                }
            }
            .foregroundColor(.secondary)

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Uninstall", role: .destructive) {
                    currentStep = .inProgress
                    performUninstall()
                }
            }
        }
        .padding()
    }

    @ViewBuilder
    private var progressStep: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)

            Text("Uninstalling...")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(completedSteps, id: \.self) { step in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(step)
                    }
                    .font(.caption)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var completeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Uninstall Complete")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(completedSteps, id: \.self) { step in
                    HStack {
                        Image(systemName: "checkmark")
                            .foregroundColor(.green)
                        Text(step)
                    }
                    .font(.caption)
                }
            }

            Divider()

            VStack(spacing: 8) {
                Text("To complete removal:")
                    .font(.subheadline)
                Text("Drag TermQ.app to the Trash")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if removeAppData {
                VStack(spacing: 4) {
                    Text("Your backup is preserved at:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(BackupManager.backupFilePath)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Actions

    private func performBackup() {
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)

            let result = BackupManager.backup()

            await MainActor.run {
                switch result {
                case .success:
                    currentStep = .confirmation
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    // Still proceed to confirmation but show error
                    currentStep = .confirmation
                }
            }
        }
    }

    private func performUninstall() {
        Task {
            // Remove CLI tool
            if removeCLI, let location = CLIInstaller.currentInstallLocation {
                let result = await CLIInstaller.uninstall(from: location)
                await MainActor.run {
                    if case .success = result {
                        completedSteps.append("Removed CLI Tool")
                    }
                }
            }

            // Remove MCP server
            if removeMCP, let location = MCPServerInstaller.currentInstallLocation {
                let result = await MCPServerInstaller.uninstall(from: location)
                await MainActor.run {
                    if case .success = result {
                        completedSteps.append("Removed MCP Server")
                    }
                }
            }

            // Remove app data
            if removeAppData {
                let appSupportPath = BackupManager.primaryBoardPath.deletingLastPathComponent().path
                do {
                    try FileManager.default.removeItem(atPath: appSupportPath)
                    await MainActor.run {
                        completedSteps.append("Removed App Data")
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Failed to remove app data: \(error.localizedDescription)"
                    }
                }
            }

            await MainActor.run {
                currentStep = .complete
            }
        }
    }
}
