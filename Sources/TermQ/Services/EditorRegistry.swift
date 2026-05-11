import AppKit
import TermQShared

@MainActor
final class EditorRegistry: ObservableObject {
    static let shared = EditorRegistry()

    @Published private(set) var available: [ExternalEditor] = []

    private let workspace: any WorkspaceProvider
    private let commandRunner: any YNHCommandRunner

    private convenience init() {
        self.init(workspace: LiveWorkspaceProvider(), commandRunner: LiveYNHCommandRunner())
    }

    init(
        workspace: any WorkspaceProvider,
        commandRunner: any YNHCommandRunner = LiveYNHCommandRunner()
    ) {
        self.workspace = workspace
        self.commandRunner = commandRunner
    }

    func start() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.available = await self.detect()
        }
    }

    private struct Candidate {
        let kind: ExternalEditor.Kind
        let displayName: String
        let bundleID: String
        let cli: String?
    }

    private func detect() async -> [ExternalEditor] {
        let candidates: [Candidate] = [
            Candidate(kind: .xcode, displayName: "Xcode", bundleID: "com.apple.dt.Xcode", cli: "xed"),
            Candidate(kind: .vscode, displayName: "VS Code", bundleID: "com.microsoft.VSCode", cli: "code"),
            Candidate(kind: .cursor, displayName: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92", cli: "cursor"),
            Candidate(kind: .intellij, displayName: "IntelliJ IDEA", bundleID: "com.jetbrains.intellij", cli: "idea"),
            Candidate(
                kind: .intellijCE, displayName: "IntelliJ CE",
                bundleID: "com.jetbrains.intellij.ce", cli: "idea"),
        ]

        var result: [ExternalEditor] = []

        for candidate in candidates {
            if let url = workspace.urlForApplication(withBundleIdentifier: candidate.bundleID) {
                result.append(ExternalEditor(kind: candidate.kind, displayName: candidate.displayName, appURL: url))
            } else if let cli = candidate.cli, let url = await which(cli) {
                result.append(ExternalEditor(kind: candidate.kind, displayName: candidate.displayName, appURL: url))
            }
        }

        return result
    }

    private func which(_ binary: String) async -> URL? {
        guard
            let result = try? await commandRunner.run(
                executable: "/usr/bin/which",
                arguments: [binary],
                environment: nil
            ),
            result.didSucceed
        else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed)
    }
}
