import SwiftUI
import TermQCore

/// Environment settings tab - global environment variables and secret management
struct SettingsEnvironmentView: View {
    @ObservedObject private var envManager = GlobalEnvironmentManager.shared
    @State private var newKey: String = ""
    @State private var newValue: String = ""
    @State private var newIsSecret: Bool = false
    @State private var editingVariable: EnvironmentVariable?
    @State private var showResetKeyConfirmation = false
    @State private var hasEncryptionKey = false
    @State private var validationError: String?
    @State private var showSecretValue: Set<UUID> = []

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
        }
    }

    // MARK: - Variables Section

    @ViewBuilder
    private var variablesSection: some View {
        Section {
            if envManager.variables.isEmpty {
                Text(Strings.Settings.Environment.noVariables)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(envManager.variables) { variable in
                    variableRow(variable)
                }
            }

            // Add new variable - stacked layout for wider inputs
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Strings.Settings.Environment.keyPlaceholder)
                        .frame(width: 50, alignment: .leading)
                    TextField("", text: $newKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: newKey) { _, newValue in
                            validateNewKey(newValue)
                        }
                }

                HStack {
                    Text(Strings.Settings.Environment.valuePlaceholder)
                        .frame(width: 50, alignment: .leading)
                    TextField(
                        newIsSecret ? Strings.Settings.Environment.secretPlaceholder : "",
                        text: $newValue
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Toggle(Strings.Settings.Environment.secret, isOn: $newIsSecret)
                        .toggleStyle(.checkbox)

                    Spacer()

                    Button(Strings.Common.add) {
                        addVariable()
                    }
                    .disabled(newKey.isEmpty || newValue.isEmpty || validationError != nil)
                }

                if let error = validationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if newIsSecret || envManager.variables.contains(where: { $0.isSecret }) {
                    Text(Strings.Editor.Environment.secretWarning)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(.top, 8)
        } header: {
            Text(Strings.Settings.Environment.sectionVariables)
        }
    }

    @ViewBuilder
    private func variableRow(_ variable: EnvironmentVariable) -> some View {
        HStack {
            // Key (monospaced)
            Text(variable.key)
                .font(.system(.body, design: .monospaced))
                .frame(width: 120, alignment: .leading)

            Text("=")
                .foregroundColor(.secondary)

            // Value (masked if secret)
            if variable.isSecret {
                if showSecretValue.contains(variable.id) {
                    Text(variable.value)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    Text(String(repeating: "•", count: min(variable.value.count, 20)))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Button {
                    toggleSecretVisibility(variable.id)
                } label: {
                    Image(
                        systemName: showSecretValue.contains(variable.id)
                            ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(Strings.Settings.Environment.toggleVisibility)

                Image(systemName: "lock.fill")
                    .foregroundColor(.orange)
                    .help(Strings.Settings.Environment.secretIndicator)
            } else {
                Text(variable.value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            // Delete button
            Button(role: .destructive) {
                deleteVariable(variable)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
            .help(Strings.Common.delete)
        }
        .padding(.vertical, 2)
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

    private func validateNewKey(_ key: String) {
        if key.isEmpty {
            validationError = nil
            return
        }

        let testVar = EnvironmentVariable(key: key, value: "", isSecret: false)
        if !testVar.isValidKey {
            validationError = Strings.Settings.Environment.invalidKeyError
        } else if envManager.keyExists(key) {
            validationError = Strings.Settings.Environment.duplicateKeyError
        } else if testVar.isReservedKey {
            validationError = Strings.Settings.Environment.reservedKeyWarning
        } else {
            validationError = nil
        }
    }

    private func addVariable() {
        guard !newKey.isEmpty, !newValue.isEmpty else { return }

        let variable = EnvironmentVariable(
            key: newKey,
            value: newValue,
            isSecret: newIsSecret
        )

        Task {
            do {
                try await envManager.addVariable(variable)
                await MainActor.run {
                    newKey = ""
                    newValue = ""
                    newIsSecret = false
                    validationError = nil
                }
            } catch {
                await MainActor.run {
                    validationError = error.localizedDescription
                }
            }
        }
    }

    private func deleteVariable(_ variable: EnvironmentVariable) {
        Task {
            try? await envManager.deleteVariable(id: variable.id)
        }
    }

    private func toggleSecretVisibility(_ id: UUID) {
        if showSecretValue.contains(id) {
            showSecretValue.remove(id)
        } else {
            showSecretValue.insert(id)
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
}
