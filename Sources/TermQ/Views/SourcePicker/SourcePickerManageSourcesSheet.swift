import SwiftUI
import TermQShared

/// Shared "Manage Sources" sheet — shown when the user clicks the gear icon
/// on any `SourcePicker` Library tab. Lists registered `ynh sources` with a
/// Remove button per row. Adding a source is the visible bottom-of-library
/// "Browse Local…" affordance, not a button inside this sheet.
struct SourcePickerManageSourcesSheet: View {
    @ObservedObject var sourcesService: SourcesService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Strings.Harnesses.installManageSources)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            if sourcesService.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sourcesService.sources.isEmpty {
                Text(Strings.Harnesses.installSourcesEmpty)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sourcesService.sources) { source in
                    sourceRow(source)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .listStyle(.plain)
            }

            Divider()

            HStack {
                Spacer()
                Button(Strings.Harnesses.installManageSourcesDone) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .onAppear {
            Task { await sourcesService.refresh() }
        }
    }

    @ViewBuilder
    private func sourceRow(_ source: YNHSource) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.body)
                    .fontWeight(.medium)
                Text(source.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(Strings.Harnesses.installSourcesCount(source.harnesses))
                    .font(.caption2)
                    .foregroundColor(source.harnesses == 0 ? .orange : .secondary)
            }
            Spacer()
            Button(Strings.Harnesses.installSourcesRemove) {
                Task { await sourcesService.removeSource(name: source.name) }
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
            .font(.caption)
        }
        .padding(.vertical, 2)
    }
}
