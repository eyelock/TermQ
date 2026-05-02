import SwiftUI
import TermQShared

/// Sheet for editing the safe subset of manifest fields — description,
/// default vendor, version.
///
/// Reads `.ynh-plugin/plugin.json` directly via `HarnessManifestEditor` and
/// writes specific fields back, preserving all other keys (includes,
/// delegates, $schema, etc.). Triggers a detail re-fetch on success.
struct EditManifestSheet: View {
    let harness: Harness
    let onDismiss: () -> Void

    @StateObject private var manifestEditor = HarnessManifestEditor()
    @ObservedObject private var harnessRepo: HarnessRepository = .shared
    @ObservedObject private var vendorService: VendorService = .shared

    @State private var descriptionText: String = ""
    @State private var defaultVendor: String = ""
    @State private var versionText: String = ""
    @State private var loadError: String?
    @State private var initialFields: HarnessManifestFields?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Strings.Harnesses.editManifestTitle)
                .font(.headline)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Strings.Harnesses.editManifestName)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .trailing)
                Text(harness.name)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Strings.Harnesses.editManifestVersion)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                    TextField(Strings.Harnesses.editManifestVersionPlaceholder, text: $versionText)
                        .textFieldStyle(.roundedBorder)
                    if !versionText.isEmpty && !SemverValidator.isValid(versionText) {
                        Text(Strings.Harnesses.editManifestVersionInvalid)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Strings.Harnesses.editManifestVendor)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .trailing)
                Picker("", selection: $defaultVendor) {
                    ForEach(vendorOptions, id: \.self) { vendorID in
                        Text(vendorID).tag(vendorID)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Strings.Harnesses.editManifestDescription)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(width: 100, alignment: .trailing)
                    TextEditor(text: $descriptionText)
                        .font(.system(size: 12))
                        .frame(minHeight: 80, maxHeight: 140)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                        )
                }
                Text(Strings.Harnesses.editManifestDescriptionHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 108)
            }

            if let error = loadError ?? manifestEditor.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(Strings.Harnesses.installCancel) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(manifestEditor.isWriting)

                Button(Strings.Harnesses.editManifestSave) {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .onAppear {
            load()
            Task {
                if vendorService.vendors.isEmpty {
                    await vendorService.refresh()
                }
            }
        }
    }

    private var vendorOptions: [String] {
        // VendorService loads asynchronously. Until it returns, fall back to
        // the harness's current default + the value already in the field so
        // the picker isn't empty on first render.
        var ids = vendorService.vendors.map(\.vendorID)
        for fallback in [defaultVendor, harness.defaultVendor] where !fallback.isEmpty && !ids.contains(fallback) {
            ids.append(fallback)
        }
        return ids
    }

    private var hasChanges: Bool {
        guard let initial = initialFields else { return false }
        return current != initial
    }

    private var current: HarnessManifestFields {
        HarnessManifestFields(
            description: descriptionText,
            defaultVendor: defaultVendor,
            version: versionText
        )
    }

    private var canSave: Bool {
        !manifestEditor.isWriting
            && hasChanges
            && !defaultVendor.isEmpty
            && !versionText.isEmpty
            && SemverValidator.isValid(versionText)
    }

    private func load() {
        do {
            let fields = try HarnessManifestEditor.read(at: harness.editablePath)
            descriptionText = fields.description
            defaultVendor = fields.defaultVendor
            versionText = fields.version
            initialFields = fields
        } catch let err as HarnessManifestEditorError {
            loadError = manifestEditor.errorMessage ?? Self.loadErrorMessage(err)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() async {
        let ok = await manifestEditor.apply(
            at: harness.editablePath,
            harnessName: harness.name,
            fields: current,
            repository: harnessRepo
        )
        if ok { onDismiss() }
    }

    private static func loadErrorMessage(_ err: HarnessManifestEditorError) -> String {
        switch err {
        case .fileNotFound(let path): return "Manifest not found at \(path)"
        case .invalidJSON(let detail): return "Manifest is malformed: \(detail)"
        case .writeFailed(let detail): return "Failed to write manifest: \(detail)"
        }
    }
}
