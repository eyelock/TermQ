import SwiftUI
import TermQCore

/// Environment variables tab for the terminal card editor
struct CardEditorEnvironmentTab: View {
    @Binding var environmentVariables: [EnvironmentVariable]
    let cardId: UUID

    @ObservedObject private var globalEnvManager = GlobalEnvironmentManager.shared
    @State private var items: [KeyValueItem] = []
    @State private var showSettings = false

    // Existing keys for duplicate checking
    private var existingKeys: Set<String> {
        Set(environmentVariables.map { $0.key })
    }

    var body: some View {
        Group {
            Section {
                Text(Strings.Editor.Environment.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(Strings.Editor.Environment.sectionTerminal) {
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
        .onAppear {
            syncItems()
        }
        .onChange(of: environmentVariables) { _, _ in
            syncItems()
        }
    }

    // MARK: - Variable Rows

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

    private func addVariable(key: String, value: String, isSecret: Bool) {
        let variable = EnvironmentVariable(
            key: key,
            value: value,
            isSecret: isSecret
        )

        // If secret, store in SecureStorage
        if isSecret {
            Task {
                do {
                    try await SecureStorage.shared.storeSecret(
                        id: "terminal-\(cardId.uuidString)-\(variable.id.uuidString)",
                        value: value
                    )
                    await MainActor.run {
                        // Store with empty value (secret stored separately)
                        let storedVar = EnvironmentVariable(
                            id: variable.id,
                            key: variable.key,
                            value: "",  // Don't store secret in card
                            isSecret: true
                        )
                        environmentVariables.append(storedVar)
                    }
                } catch {
                    // Handle error
                }
            }
        } else {
            environmentVariables.append(variable)
        }
    }

    private func deleteVariable(id: UUID) {
        if let variable = environmentVariables.first(where: { $0.id == id }) {
            if variable.isSecret {
                Task {
                    try? await SecureStorage.shared.deleteSecret(
                        id: "terminal-\(cardId.uuidString)-\(id.uuidString)"
                    )
                }
            }
            environmentVariables.removeAll { $0.id == id }
        }
    }

    private func syncItems() {
        items = environmentVariables.map { variable in
            KeyValueItem(
                id: variable.id,
                key: variable.key,
                value: variable.value,
                isSecret: variable.isSecret
            )
        }
    }
}
