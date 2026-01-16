import SwiftUI
import TermQCore

/// Environment variables tab for the terminal card editor
struct CardEditorEnvironmentTab: View {
    @Binding var environmentVariables: [EnvironmentVariable]
    let cardId: UUID

    @ObservedObject private var globalEnvManager = GlobalEnvironmentManager.shared
    @State private var newKey: String = ""
    @State private var newValue: String = ""
    @State private var newIsSecret: Bool = false
    @State private var validationError: String?
    @State private var showSecretValue: Set<UUID> = []
    @State private var showSettings = false

    var body: some View {
        Section {
            Text(Strings.Editor.Environment.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }

        Section(Strings.Editor.Environment.sectionTerminal) {
            if environmentVariables.isEmpty {
                Text(Strings.Editor.Environment.noVariables)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(environmentVariables) { variable in
                    terminalVariableRow(variable)
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

                if newIsSecret || environmentVariables.contains(where: { $0.isSecret }) {
                    Text(Strings.Editor.Environment.secretWarning)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(.top, 8)
        }

        Section(Strings.Editor.Environment.sectionInherited) {
            if globalEnvManager.variables.isEmpty {
                Text(Strings.Editor.Environment.noGlobalVariables)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(globalEnvManager.variables) { variable in
                    globalVariableRow(variable)
                }
            }

            HStack {
                Spacer()
                Button(Strings.Editor.Environment.editGlobal) {
                    showSettings = true
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView(initialTab: .environment)
                }
            }
        }
    }

    // MARK: - Variable Rows

    @ViewBuilder
    private func terminalVariableRow(_ variable: EnvironmentVariable) -> some View {
        HStack {
            Text(variable.key)
                .font(.system(.body, design: .monospaced))
                .frame(width: 120, alignment: .leading)

            Text("=")
                .foregroundColor(.secondary)

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

                Image(systemName: "lock.fill")
                    .foregroundColor(.orange)
            } else {
                Text(variable.value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            // Override indicator
            if globalEnvManager.keyExists(variable.key) {
                Text(Strings.Editor.Environment.overrides)
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
            }

            Spacer()

            Button(role: .destructive) {
                deleteVariable(variable)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func globalVariableRow(_ variable: EnvironmentVariable) -> some View {
        HStack {
            Text(variable.key)
                .font(.system(.body, design: .monospaced))
                .frame(width: 120, alignment: .leading)

            Text("=")
                .foregroundColor(.secondary)

            if variable.isSecret {
                Text(String(repeating: "•", count: 8))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)

                Image(systemName: "lock.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            } else {
                Text(variable.value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            // Show if overridden by terminal var
            if environmentVariables.contains(where: {
                $0.key.uppercased() == variable.key.uppercased()
            }) {
                Text(Strings.Editor.Environment.overridden)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
                    .strikethrough()
            }

            Text(Strings.Editor.Environment.global)
                .font(.caption2)
                .foregroundColor(.blue)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func validateNewKey(_ key: String) {
        if key.isEmpty {
            validationError = nil
            return
        }

        let testVar = EnvironmentVariable(key: key, value: "", isSecret: false)
        if !testVar.isValidKey {
            validationError = Strings.Settings.Environment.invalidKeyError
        } else if environmentVariables.contains(where: { $0.key.uppercased() == key.uppercased() }) {
            validationError = Strings.Settings.Environment.duplicateKeyError
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

        // If secret, store in SecureStorage
        if newIsSecret {
            Task {
                do {
                    try await SecureStorage.shared.storeSecret(
                        id: "terminal-\(cardId.uuidString)-\(variable.id.uuidString)",
                        value: newValue
                    )
                    await MainActor.run {
                        // Store with empty value (secret stored separately)
                        var storedVar = variable
                        storedVar = EnvironmentVariable(
                            id: variable.id,
                            key: variable.key,
                            value: "",  // Don't store secret in card
                            isSecret: true
                        )
                        environmentVariables.append(storedVar)
                        clearInputs()
                    }
                } catch {
                    await MainActor.run {
                        validationError = error.localizedDescription
                    }
                }
            }
        } else {
            environmentVariables.append(variable)
            clearInputs()
        }
    }

    private func deleteVariable(_ variable: EnvironmentVariable) {
        if variable.isSecret {
            Task {
                try? await SecureStorage.shared.deleteSecret(
                    id: "terminal-\(cardId.uuidString)-\(variable.id.uuidString)"
                )
            }
        }
        environmentVariables.removeAll { $0.id == variable.id }
    }

    private func toggleSecretVisibility(_ id: UUID) {
        if showSecretValue.contains(id) {
            showSecretValue.remove(id)
        } else {
            // Fetch secret value for display
            Task {
                if let value = try? await SecureStorage.shared.retrieveSecret(
                    id: "terminal-\(cardId.uuidString)-\(id.uuidString)")
                {
                    await MainActor.run {
                        // Temporarily update the variable value for display
                        if let index = environmentVariables.firstIndex(where: { $0.id == id }) {
                            environmentVariables[index] = EnvironmentVariable(
                                id: id,
                                key: environmentVariables[index].key,
                                value: value,
                                isSecret: true
                            )
                        }
                        showSecretValue.insert(id)
                    }
                }
            }
        }
    }

    private func clearInputs() {
        newKey = ""
        newValue = ""
        newIsSecret = false
        validationError = nil
    }
}
