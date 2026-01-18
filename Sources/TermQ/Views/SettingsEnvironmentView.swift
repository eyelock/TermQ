import SwiftUI
import TermQCore

/// Environment settings tab - global environment variables and secret management
struct SettingsEnvironmentView: View {
    @ObservedObject private var envManager = GlobalEnvironmentManager.shared
    @State private var showResetKeyConfirmation = false
    @State private var hasEncryptionKey = false
    @State private var items: [KeyValueItem] = []

    // Existing keys for duplicate checking
    private var existingKeys: Set<String> {
        Set(envManager.variables.map { $0.key })
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                variablesSection
                securitySection
            }
            .formStyle(.grouped)
        }
        .onAppear {
            checkEncryptionKey()
            syncItems()
        }
        .onChange(of: envManager.variables) { _, _ in
            syncItems()
        }
    }

    // MARK: - Variables Section

    @ViewBuilder
    private var variablesSection: some View {
        Section {
            KeyValueEditor(
                items: $items,
                config: .environmentVariables,
                existingKeys: existingKeys,
                onAdd: { key, value, isSecret in
                    addVariable(key: key, value: value, isSecret: isSecret)
                },
                onDelete: { id in
                    deleteVariable(id: id)
                }
            )
        } header: {
            Text(Strings.Settings.Environment.sectionVariables)
        }
    }

    // MARK: - Security Section

    @ViewBuilder
    private var securitySection: some View {
        Section {
            HStack {
                Text(Strings.Settings.Environment.encryptionStatus)
                Spacer()
                if hasEncryptionKey {
                    Label(
                        Strings.Settings.Environment.encryptionActive,
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundColor(.green)
                } else {
                    Label(
                        Strings.Settings.Environment.encryptionInactive,
                        systemImage: "xmark.circle.fill"
                    )
                    .foregroundColor(.red)
                }
            }

            Button(Strings.Settings.Environment.resetEncryptionKey, role: .destructive) {
                showResetKeyConfirmation = true
            }

            Text(Strings.Settings.Environment.resetEncryptionKeyWarning)
                .font(.caption)
                .foregroundColor(.orange)

            DisclosureGroup(Strings.Settings.Environment.troubleshooting) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Strings.Settings.Environment.troubleshootingIntro)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. " + Strings.Settings.Environment.troubleshootingStep1)
                        Text("2. " + Strings.Settings.Environment.troubleshootingStep2)
                        Text("3. " + Strings.Settings.Environment.troubleshootingStep3)
                        Text("4. " + Strings.Settings.Environment.troubleshootingStep4)
                        Text("5. " + Strings.Settings.Environment.troubleshootingStep5)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        } header: {
            Text(Strings.Settings.Environment.sectionSecurity)
        }
        .confirmationDialog(
            Strings.Settings.Environment.resetConfirmTitle,
            isPresented: $showResetKeyConfirmation,
            titleVisibility: .visible
        ) {
            Button(Strings.Settings.Environment.resetConfirmButton, role: .destructive) {
                resetEncryptionKey()
            }
            Button(Strings.Common.cancel, role: .cancel) {}
        } message: {
            Text(Strings.Settings.Environment.resetConfirmMessage)
        }
    }

    // MARK: - Actions

    private func checkEncryptionKey() {
        Task {
            let hasKey = await SecureStorage.shared.hasEncryptionKey()
            await MainActor.run {
                hasEncryptionKey = hasKey
            }
        }
    }

    private func addVariable(key: String, value: String, isSecret: Bool) {
        let variable = EnvironmentVariable(
            key: key,
            value: value,
            isSecret: isSecret
        )

        Task {
            try? await envManager.addVariable(variable)
        }
    }

    private func deleteVariable(id: UUID) {
        Task {
            try? await envManager.deleteVariable(id: id)
        }
    }

    private func resetEncryptionKey() {
        Task {
            do {
                try await SecureStorage.shared.resetEncryptionKey()
                await envManager.load()
                await MainActor.run {
                    hasEncryptionKey = false
                    checkEncryptionKey()
                }
            } catch {
                // Handle error
            }
        }
    }

    private func syncItems() {
        items = envManager.variables.map { variable in
            KeyValueItem(
                id: variable.id,
                key: variable.key,
                value: variable.value,
                isSecret: variable.isSecret
            )
        }
    }
}
