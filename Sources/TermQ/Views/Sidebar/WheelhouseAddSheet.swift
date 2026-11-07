import AppKit
import SwiftUI
import TermQShared

/// Adds a Wheelhouse from a pasted path, or from a folder picked in a panel.
struct WheelhouseAddSheet: View {
    /// Adds the Wheelhouse at a normalised root; nil on success, else why not.
    let onAdd: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var failure: String?
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.Wheelhouse.addWheelhouse)
                .font(.headline)
            Text(Strings.Wheelhouse.addPanelMessage)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                TextField(Strings.Wheelhouse.addPathPlaceholder, text: $path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(add)
                Button(Strings.Wheelhouse.addChooseFolder, action: chooseFolder)
            }
            if let failure {
                Text(Strings.Wheelhouse.addFailedTitle + ": " + failure)
                    .font(.caption)
                    .foregroundColor(.red)
                    .textSelection(.enabled)
            }
            HStack {
                if adding { ProgressView().controlSize(.small) }
                Spacer()
                Button(Strings.Common.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(Strings.Wheelhouse.addButton, action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(adding || WheelhouseLoader.normalizedRoot(path) == nil)
            }
        }
        .padding(16)
        .frame(width: 520)
    }

    /// Opens the folder panel, starting at the typed path when it exists.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = Strings.Wheelhouse.addButton
        panel.message = Strings.Wheelhouse.addPanelMessage
        if let root = WheelhouseLoader.normalizedRoot(path) {
            panel.directoryURL = URL(fileURLWithPath: root, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.standardizedFileURL.path
        failure = nil
    }

    private func add() {
        guard !adding, let root = WheelhouseLoader.normalizedRoot(path) else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else {
            failure = Strings.Wheelhouse.addNoFolder(root)
            return
        }
        adding = true
        failure = nil
        Task {
            let result = await onAdd(root)
            adding = false
            if let result { failure = result } else { dismiss() }
        }
    }
}
