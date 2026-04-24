import SwiftUI
import TermQShared

/// Sheet for adding a YNH marketplace via `ynh registry add <url>`.
struct AddYNHMarketplaceSheet: View {
    @ObservedObject var detector: YNHDetector
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @StateObject private var runner = MarketplaceAddRunner()
    @State private var done = false

    private var ynhPath: String? {
        if case .ready(let ynhPath, _, _) = detector.status { return ynhPath }
        return nil
    }

    private var ynhEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let override = YNHDetector.shared.ynhHomeOverride { env["YNH_HOME"] = override }
        return env
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 480, height: 320)
    }

    private var headerRow: some View {
        HStack {
            Text(Strings.Harnesses.addMarketplaceTitle).font(.headline)
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if done {
            successState
        } else if runner.isRunning {
            progressState
        } else {
            formState
        }
    }

    private var formState: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Harnesses.addMarketplaceURLLabel)
                    .font(.caption).foregroundColor(.secondary)
                TextField("https://github.com/owner/repo.git", text: $url)
                    .textFieldStyle(.roundedBorder)
            }

            Text(Strings.Harnesses.addMarketplaceHint)
                .font(.caption).foregroundColor(.secondary)

            if let err = runner.errorMessage {
                Label(err, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundColor(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var progressState: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(runner.outputLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: runner.outputLines.count) { _, count in
                if count > 0 { proxy.scrollTo(count - 1) }
            }
        }
    }

    private var successState: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text(Strings.Harnesses.addMarketplaceSuccess).font(.headline)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(runner.outputLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(done ? Strings.Common.close : Strings.Common.cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(runner.isRunning)
            Spacer()
            if !done && !runner.isRunning {
                Button(Strings.Harnesses.addMarketplaceButton) {
                    Task { await addRegistry() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty || ynhPath == nil)
            }
        }
        .padding()
    }

    private func addRegistry() async {
        guard let ynhPath, !url.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        await runner.run(
            ynhPath: ynhPath,
            url: url.trimmingCharacters(in: .whitespaces),
            environment: ynhEnvironment
        )
        if runner.succeeded { done = true }
    }
}
