import AppKit
import TermQShared

@MainActor
final class EditorRegistry: ObservableObject {
    static let shared = EditorRegistry()

    @Published private(set) var available: [ExternalEditor] = []

    private init() {}

    func start() {
        available = detect()
    }

    private struct Candidate {
        let kind: ExternalEditor.Kind
        let displayName: String
        let bundleID: String
        let cli: String?
    }

    private func detect() -> [ExternalEditor] {
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
        let ws = NSWorkspace.shared

        for candidate in candidates {
            if let url = ws.urlForApplication(withBundleIdentifier: candidate.bundleID) {
                result.append(ExternalEditor(kind: candidate.kind, displayName: candidate.displayName, appURL: url))
            } else if let cli = candidate.cli, let url = which(cli) {
                result.append(ExternalEditor(kind: candidate.kind, displayName: candidate.displayName, appURL: url))
            }
        }

        return result
    }

    private func which(_ binary: String) -> URL? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [binary]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let path = raw, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}
