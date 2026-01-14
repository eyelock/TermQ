import SwiftUI

struct LanguagePickerView: View {
    @Binding var selectedLanguage: SupportedLanguage
    @State private var languageSearchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Currently selected display
            LabeledContent("Current") {
                if selectedLanguage.code.isEmpty {
                    Text("System Default")
                        .foregroundColor(.secondary)
                } else {
                    Text("\(selectedLanguage.nativeName) (\(selectedLanguage.code))")
                }
            }

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search languages...", text: $languageSearchText)
                    .textFieldStyle(.plain)
                if !languageSearchText.isEmpty {
                    Button {
                        languageSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            // Language list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredLanguages) { language in
                        languageRow(for: language)
                    }
                }
            }
            .frame(height: 200)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            // Current selection info
            if selectedLanguage.code.isEmpty {
                Text("Using system language preference")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Restart TermQ for language change to take effect")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private var filteredLanguages: [SupportedLanguage] {
        if languageSearchText.isEmpty {
            return SupportedLanguage.allWithDefault
        }
        let search = languageSearchText.lowercased()
        return SupportedLanguage.allWithDefault.filter {
            $0.searchableText.contains(search)
        }
    }

    @ViewBuilder
    private func languageRow(for language: SupportedLanguage) -> some View {
        Button {
            if LanguageManager.needsRestart(for: language.code) {
                LanguageManager.preferredLanguage = language.code
                selectedLanguage = language
            }
        } label: {
            HStack {
                if selectedLanguage.code == language.code {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                        .frame(width: 20)
                } else {
                    Color.clear.frame(width: 20)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if language.code.isEmpty {
                        Text("System Default")
                            .fontWeight(selectedLanguage.code == language.code ? .semibold : .regular)
                    } else {
                        Text(language.nativeName)
                            .fontWeight(selectedLanguage.code == language.code ? .semibold : .regular)
                        if language.nativeName != language.englishName {
                            Text("\(language.englishName) (\(language.code))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("(\(language.code))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            selectedLanguage.code == language.code
                ? Color.accentColor.opacity(0.1)
                : Color.clear
        )
        .cornerRadius(4)
    }
}
