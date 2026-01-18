import AppKit
import SwiftUI

/// Two-line path/directory input with browse button
///
/// Features:
/// - Two-line layout with label and full-width input
/// - Consistent monospaced styling
/// - Built-in browse functionality
/// - Optional path validation with warning indicator
///
/// Usage:
/// ```swift
/// PathInputField(
///     label: "Default Working Directory",
///     path: $defaultWorkingDirectory,
///     helpText: "Path to use as default working directory",
///     validatePath: true
/// )
/// ```
struct PathInputField: View {
    let label: String
    @Binding var path: String
    let helpText: String?
    let validatePath: Bool

    @State private var pathExists: Bool = true

    init(
        label: String,
        path: Binding<String>,
        helpText: String? = nil,
        validatePath: Bool = false
    ) {
        self.label = label
        self._path = path
        self.helpText = helpText
        self.validatePath = validatePath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Line 1: Label with Browse button
            HStack {
                Text(label)
                    .foregroundColor(.primary)

                Spacer()

                Button(Strings.Common.browse) {
                    browsePath()
                }
            }

            // Line 2: Full-width path input
            HStack(spacing: 4) {
                TextField("", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .onChange(of: path) { _, newValue in
                        if validatePath {
                            checkPathExists(newValue)
                        }
                    }

                // Path validation warning
                if validatePath && !path.isEmpty && !pathExists {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .help("Path does not exist")
                }
            }
        }
        .help(helpText ?? "")
        .onAppear {
            if validatePath {
                checkPathExists(path)
            }
        }
    }

    // MARK: - Actions

    private func browsePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = Strings.Common.select
        panel.message = label

        // Pre-select current path if it exists
        if !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                panel.directoryURL = url
            }
        }

        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }

    private func checkPathExists(_ path: String) {
        if path.isEmpty {
            pathExists = true
            return
        }

        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        pathExists =
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
