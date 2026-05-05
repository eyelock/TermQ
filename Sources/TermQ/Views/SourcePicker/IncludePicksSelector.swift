import SwiftUI

/// Checkbox list of artifact paths used by the Add Include picker's
/// Configure stage and the Edit Include sheet. Caller owns the selection
/// set; this view is a pure renderer with loading and error states.
struct IncludePicksSelector: View {
    let availablePicks: [String]
    @Binding var selected: Set<String>
    var isLoading: Bool = false
    var loadError: String?
    var emptyMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Strings.Harnesses.addIncludePicksPrompt)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(Strings.Marketplace.Picker.selectAll) {
                    selected = Set(availablePicks)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .font(.caption)
                .disabled(availablePicks.isEmpty)
                Text("·").foregroundColor(.secondary).font(.caption)
                Button(Strings.Marketplace.Picker.selectNone) {
                    selected = []
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .font(.caption)
                .disabled(selected.isEmpty)
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(Strings.Marketplace.pluginLoadingArtifacts)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let err = loadError {
            Label(err, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(.orange)
        } else if availablePicks.isEmpty {
            Text(emptyMessage ?? Strings.Marketplace.pluginNoArtifacts)
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(availablePicks, id: \.self) { pick in
                        pickRow(pick)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 140, maxHeight: 240)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func pickRow(_ pick: String) -> some View {
        let isSelected = selected.contains(pick)
        return Button {
            if isSelected { selected.remove(pick) } else { selected.insert(pick) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                Text(pick).font(.system(size: 12, design: .monospaced))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
