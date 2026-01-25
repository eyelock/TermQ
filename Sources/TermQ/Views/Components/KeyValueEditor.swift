import SwiftUI
import TermQCore

/// Configuration for KeyValueEditor component
struct KeyValueEditorConfig: Sendable {
    let showSecretToggle: Bool
    let keyLabel: String
    let valueLabel: String
    let addButtonText: String
    let validateKey: (@Sendable (String) -> String?)?

    /// Default configuration for environment variables
    static let environmentVariables = KeyValueEditorConfig(
        showSecretToggle: true,
        keyLabel: "Key",
        valueLabel: "Value",
        addButtonText: Strings.Common.add,
        validateKey: { key in
            let testVar = EnvironmentVariable(key: key, value: "", isSecret: false)
            if !testVar.isValidKey {
                return Strings.Settings.Environment.invalidKeyError
            } else if testVar.isReservedKey {
                return Strings.Settings.Environment.reservedKeyWarning
            }
            return nil
        }
    )

    /// Default configuration for tags
    static let tags = KeyValueEditorConfig(
        showSecretToggle: false,
        keyLabel: "Key",
        valueLabel: "Value",
        addButtonText: Strings.Common.add,
        validateKey: nil
    )
}

/// Item type for KeyValueEditor
struct KeyValueItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let key: String
    let value: String
    let isSecret: Bool

    init(id: UUID = UUID(), key: String, value: String, isSecret: Bool = false) {
        self.id = id
        self.key = key
        self.value = value
        self.isSecret = isSecret
    }
}

/// List of existing key=value items with delete functionality
struct KeyValueList: View {
    @Binding var items: [KeyValueItem]
    let onDelete: (UUID) -> Void
    let emptyMessage: String?

    @State private var showSecretValue: Set<UUID> = []

    init(items: Binding<[KeyValueItem]>, onDelete: @escaping (UUID) -> Void, emptyMessage: String? = nil) {
        self._items = items
        self.onDelete = onDelete
        self.emptyMessage = emptyMessage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                Text(emptyMessage ?? Strings.Settings.Environment.noVariables)
                    .foregroundColor(.secondary)
                    .font(.callout)
            } else {
                ForEach(items) { item in
                    itemRow(item)
                }
            }
        }
    }

    @ViewBuilder
    private func itemRow(_ item: KeyValueItem) -> some View {
        HStack {
            // Key (monospaced)
            Text(item.key)
                .font(.system(.body, design: .monospaced))
                .frame(width: 120, alignment: .leading)

            Text("=")
                .foregroundColor(.secondary)

            // Value (masked if secret)
            if item.isSecret {
                if showSecretValue.contains(item.id) {
                    Text(item.value)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    Text(String(repeating: "•", count: min(item.value.count, 20)))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Button {
                    toggleSecretVisibility(item.id)
                } label: {
                    Image(
                        systemName: showSecretValue.contains(item.id)
                            ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(Strings.Settings.Environment.toggleVisibility)

                Image(systemName: "lock.fill")
                    .foregroundColor(.orange)
                    .help(Strings.Settings.Environment.secretIndicator)
            } else {
                Text(item.value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            // Delete button
            Button(role: .destructive) {
                onDelete(item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
            .help(Strings.Common.delete)
        }
        .padding(.vertical, 2)
    }

    private func toggleSecretVisibility(_ id: UUID) {
        if showSecretValue.contains(id) {
            showSecretValue.remove(id)
        } else {
            showSecretValue.insert(id)
        }
    }
}

/// Form for adding new key=value items
struct KeyValueAddForm: View {
    let config: KeyValueEditorConfig
    let existingKeys: Set<String>
    let items: [KeyValueItem]
    let onAdd: (String, String, Bool) -> Void

    @State private var newKey: String = ""
    @State private var newValue: String = ""
    @State private var newIsSecret: Bool = false
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Key input
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(config.keyLabel)
                        .foregroundColor(.primary)
                    Spacer()
                }

                TextField("", text: $newKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: newKey) { _, newValue in
                        validateNewKey(newValue)
                    }
            }

            // Value input
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(config.valueLabel)
                        .foregroundColor(.primary)
                    Spacer()
                }

                TextField(
                    newIsSecret ? Strings.Settings.Environment.secretPlaceholder : "",
                    text: $newValue
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            }

            // Secret toggle (if enabled) + Add button
            HStack {
                if config.showSecretToggle {
                    Toggle(Strings.Settings.Environment.secret, isOn: $newIsSecret)
                        .toggleStyle(.checkbox)
                }

                Spacer()

                Button(config.addButtonText) {
                    addItem()
                }
                .disabled(newKey.isEmpty || newValue.isEmpty || validationError != nil)
            }

            // Validation error
            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Secret warning
            if config.showSecretToggle && (newIsSecret || items.contains(where: { $0.isSecret })) {
                Text(Strings.Editor.Environment.secretWarning)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private func validateNewKey(_ key: String) {
        if key.isEmpty {
            validationError = nil
            return
        }

        // Check for duplicate keys
        if existingKeys.contains(key) || items.contains(where: { $0.key == key }) {
            validationError = Strings.Settings.Environment.duplicateKeyError
            return
        }

        // Custom validation if provided
        if let validator = config.validateKey {
            validationError = validator(key)
        } else {
            validationError = nil
        }
    }

    private func addItem() {
        guard !newKey.isEmpty, !newValue.isEmpty, validationError == nil else { return }

        onAdd(newKey, newValue, newIsSecret)

        // Reset form
        newKey = ""
        newValue = ""
        newIsSecret = false
        validationError = nil
    }
}

/// Unified key=value editor for environment variables and tags (DEPRECATED - use KeyValueList + KeyValueAddForm)
///
/// Features:
/// - Full-width text inputs
/// - Configurable "Secret" toggle
/// - Proper validation and error display
/// - Consistent styling and alignment
/// - Display existing entries with delete functionality
///
/// Usage:
/// ```swift
/// KeyValueEditor(
///     items: $environmentVariables,
///     config: .environmentVariables,
///     existingKeys: existingKeys,
///     onAdd: { key, value, isSecret in
///         // Handle adding new item
///     },
///     onDelete: { id in
///         // Handle deleting item
///     }
/// )
/// ```
struct KeyValueEditor: View {
    @Binding var items: [KeyValueItem]
    let config: KeyValueEditorConfig
    let existingKeys: Set<String>
    let onAdd: (String, String, Bool) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            KeyValueList(items: $items, onDelete: onDelete)
            KeyValueAddForm(
                config: config,
                existingKeys: existingKeys,
                items: items,
                onAdd: onAdd
            )
        }
    }
}
