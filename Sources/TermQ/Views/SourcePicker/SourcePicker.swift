import SwiftUI

/// Two-tab picker shell — Library | Git URL — driven by a
/// ``SourcePickerContext``. Owns the tab selection and chrome (header,
/// segmented picker, divider, cancel button); the context owns all
/// per-tab content and apply behaviour.
struct SourcePicker<Context: SourcePickerContext>: View {
    @ObservedObject var context: Context
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable {
        case library
        case gitURL
    }

    @State private var selectedTab: Tab = .library

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Picker("", selection: $selectedTab) {
                Text(Strings.Harnesses.installTabLibrary).tag(Tab.library)
                Text(Strings.Harnesses.installTabGit).tag(Tab.gitURL)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            switch selectedTab {
            case .library: context.library
            case .gitURL: context.gitURLView
            }

            Divider()

            HStack {
                Button(Strings.Harnesses.installCancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            Text(context.title)
                .font(.headline)
            Spacer()
        }
        .padding()
    }
}
