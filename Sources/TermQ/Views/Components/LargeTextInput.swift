import SwiftUI

/// Large multi-line text input with label and optional help tooltip
///
/// Features:
/// - Consistent label styling
/// - Multi-line text editing (3-8 lines default)
/// - Optional help tooltip
/// - Placeholder text support
/// - Consistent styling with PathInputField and SharedToggle
/// - Fixed height to prevent layout jumping
///
/// Usage:
/// ```swift
/// LargeTextInput(
///     label: "Persistent Context",
///     text: $llmPrompt,
///     placeholder: "Enter context for the LLM agent",
///     helpText: "This context is sent with every agent request"
/// )
/// ```
struct LargeTextInput: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    let helpText: String?
    let minLines: Int
    let maxLines: Int

    init(
        label: String,
        text: Binding<String>,
        placeholder: String = "",
        helpText: String? = nil,
        minLines: Int = 3,
        maxLines: Int = 8
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.helpText = helpText
        self.minLines = minLines
        self.maxLines = maxLines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Label with optional help icon
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let helpText = helpText {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.secondary)
                        .imageScale(.small)
                        .help(helpText)
                }
            }

            // Multi-line text editor with fixed height
            ZStack(alignment: .topLeading) {
                // Placeholder text
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }

                // Text editor
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
            .frame(height: 100)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
