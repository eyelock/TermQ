import SwiftUI

/// Toggle that respects global setting and shows disabled state
///
/// Features:
/// - Shows toggle if global setting allows
/// - Shows disabled message with secondary styling if global blocks
/// - Consistent messaging across all uses
/// - Optional help text support
/// - Optional clickable link to open settings
///
/// Usage:
/// ```swift
/// SharedToggle(
///     label: "Allow Agent Prompts",
///     isOn: $allowAutorun,
///     isGloballyEnabled: enableTerminalAutorun,
///     disabledMessage: "Disabled globally",
///     helpText: "Allow this terminal to run agent prompts"
/// )
/// ```
struct SharedToggle: View {
    let label: String
    @Binding var isOn: Bool
    let isGloballyEnabled: Bool
    let disabledMessage: String
    let helpText: String?
    let onDisabledTap: (() -> Void)?

    init(
        label: String,
        isOn: Binding<Bool>,
        isGloballyEnabled: Bool,
        disabledMessage: String = "Disabled globally",
        helpText: String? = nil,
        onDisabledTap: (() -> Void)? = nil
    ) {
        self.label = label
        self._isOn = isOn
        self.isGloballyEnabled = isGloballyEnabled
        self.disabledMessage = disabledMessage
        self.helpText = helpText
        self.onDisabledTap = onDisabledTap
    }

    var body: some View {
        if isGloballyEnabled {
            Toggle(label, isOn: $isOn)
                .help(helpText ?? "")
        } else {
            HStack {
                Text(label)
                    .foregroundColor(.secondary)
                Spacer()

                if let onTap = onDisabledTap {
                    Button(action: onTap) {
                        Text(disabledMessage)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.borderless)
                } else {
                    Text(disabledMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .help(helpText ?? "")
        }
    }
}
