import AppKit
import SwiftUI
import TermQShared

/// Sheet for duplicating an installed harness.
///
/// Reads the source harness manifest from `harness.path/.harness.json`, strips
/// `installed_from`, writes a new `harness.json` at `<destination>/<new-name>/`,
/// then runs `ynh install <new-path>`.
struct DuplicateHarnessSheet: View {
    let harness: Harness
    @ObservedObject var detector: YNHDetector
    @ObservedObject var repository: HarnessRepository
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultHarnessAuthorDirectory") private var defaultHarnessAuthorDirectory = ""

    @State private var name = ""
    @State private var destination = ""
    @State private var nameError: String?
    @State private var isRunning = false
    @State private var succeeded = false
    @State private var errorMessage: String?

    private var ynhPath: String? {
        if case .ready(let p, _, _) = detector.status { return p }
        return nil
    }
    private var ynhEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let override = YNHDetector.shared.ynhHomeOverride { env["YNH_HOME"] = override }
        return env
    }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedDest: String { destination.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if succeeded {
                successView
            } else if isRunning {
                progressView
            } else {
                formView
            }
            Divider()
            footer
        }
        .frame(width: 480, height: 360)
        .onAppear { loadDefaultDestination() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(Strings.HarnessDuplicate.title)
                .font(.headline)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2).foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Form

    private var formView: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("", text: $name, prompt: Text("copy-of-\(harness.name)"))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: name) { _, _ in nameError = nil }
                    if let err = nameError {
                        Text(err).font(.caption).foregroundColor(.red)
                    }
                }
            } header: {
                Text(Strings.HarnessWizard.nameLabel)
            }

            Section {
                HStack {
                    TextField("/path/to/harnesses", text: $destination)
                        .textFieldStyle(.roundedBorder)
                    Button(Strings.Common.browse) { browseDestination() }
                }
            } header: {
                Text(Strings.HarnessWizard.destinationLabel)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Progress

    private var progressView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(Strings.HarnessDuplicate.installing)
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40)).foregroundColor(.green)
            Text(Strings.HarnessDuplicate.success(trimmedName))
                .font(.title3).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let err = errorMessage {
                Text(err).font(.caption).foregroundColor(.red).lineLimit(2)
            }
            Spacer()
            if succeeded {
                Button(Strings.Common.close) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button(Strings.Common.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isRunning)
                Button(Strings.HarnessDuplicate.duplicateButton) {
                    Task { await duplicate() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || trimmedName.isEmpty || trimmedDest.isEmpty)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func browseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = Strings.Common.select
        if !trimmedDest.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: trimmedDest)
        }
        if panel.runModal() == .OK, let url = panel.url {
            destination = url.path
        }
    }

    private func loadDefaultDestination() {
        name = "copy-of-\(harness.name)"
        if !defaultHarnessAuthorDirectory.isEmpty {
            destination = defaultHarnessAuthorDirectory
            return
        }
        // Fall back to ~/Documents — never default to the ynh-managed harnesses
        // directory, which would make ynh install circular.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        destination = docs?.path ?? NSHomeDirectory()
    }

    private func validate() -> Bool {
        if trimmedName.isEmpty {
            nameError = Strings.HarnessWizard.errorNameRequired
            return false
        }
        let forbidden = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.")).inverted
        if trimmedName.rangeOfCharacter(from: forbidden) != nil {
            nameError = Strings.HarnessWizard.errorNameInvalid
            return false
        }
        if repository.harnesses.contains(where: { $0.name == trimmedName }) {
            nameError = Strings.HarnessWizard.errorNameDuplicate(trimmedName)
            return false
        }
        return true
    }

    private func duplicate() async {
        guard validate(), let ynhBin = ynhPath else { return }
        isRunning = true
        errorMessage = nil

        let newDir = (trimmedDest as NSString).appendingPathComponent(trimmedName)

        do {
            // Read source manifest
            let sourcePath = (harness.path as NSString).appendingPathComponent(".harness.json")
            let sourceData = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
            guard var manifest = try JSONSerialization.jsonObject(with: sourceData) as? [String: Any] else {
                throw DuplicateError.badManifest
            }

            // Update fields for the new harness
            manifest["name"] = trimmedName
            manifest.removeValue(forKey: "installed_from")

            // Create destination directory
            try FileManager.default.createDirectory(
                atPath: newDir,
                withIntermediateDirectories: true
            )

            // Write .harness.json — ynh install expects this filename in the source directory
            let destManifest = (newDir as NSString).appendingPathComponent(".harness.json")
            let outData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try outData.write(to: URL(fileURLWithPath: destManifest))

            // ynh install <new-path>
            let exitCode = await runProcess(ynhBin, args: ["install", newDir], environment: ynhEnvironment)
            guard exitCode == 0 else { throw DuplicateError.installFailed(exitCode) }

            await repository.refresh()
            succeeded = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }

    private func runProcess(_ executable: String, args: [String], environment: [String: String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                process.environment = environment
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                try? process.run()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus)
            }
        }
    }

    private enum DuplicateError: LocalizedError {
        case badManifest
        case installFailed(Int32)
        var errorDescription: String? {
            switch self {
            case .badManifest: "Could not read harness manifest."
            case .installFailed(let code): "ynh install failed (exit \(code))."
            }
        }
    }
}
