import SwiftUI

/// Reusable sheet that displays live-streamed command output.
///
/// Used by fork, update, and (Phase 2/3) YND tool commands. The caller
/// provides a `CommandSheetState` that drives all dynamic content; this view
/// is purely a renderer.
struct CommandRunnerSheet: View {
    let title: String
    @ObservedObject var state: CommandSheetState
    let onRerun: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            outputArea
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            statusBadge
        }
        .padding()
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch state.phase {
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(Strings.CommandRunner.running)
                    .font(.caption).foregroundColor(.secondary)
            }
        case .succeeded:
            Label(Strings.CommandRunner.succeeded, systemImage: "checkmark.circle.fill")
                .foregroundColor(.green).font(.caption)
        case .failed:
            Label(Strings.CommandRunner.failed, systemImage: "xmark.circle.fill")
                .foregroundColor(.red).font(.caption)
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Output

    private var outputArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(state.outputLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
            .onChange(of: state.outputLines.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
        }
        .frame(minHeight: 280)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                let text = state.outputLines.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Label(Strings.Common.copyOutput, systemImage: "doc.on.clipboard")
            }
            .disabled(state.outputLines.isEmpty)

            Spacer()

            if let rerun = onRerun, state.phase != .running {
                Button(Strings.Common.rerun, action: rerun)
            }

            Button(Strings.Common.close, action: onDismiss)
                .keyboardShortcut(.cancelAction)
                .disabled(state.phase == .running)
        }
        .padding()
    }
}

// MARK: - CommandSheetState

/// Observable state for a `CommandRunnerSheet`. The sheet caller drives this
/// by running a `CommandRunner` invocation and piping results in.
@MainActor
final class CommandSheetState: ObservableObject {
    enum Phase { case idle, running, succeeded, failed }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var outputLines: [String] = []
    @Published private(set) var exitCode: Int32?

    func begin() {
        outputLines = []
        exitCode = nil
        phase = .running
    }

    func append(line: String) {
        outputLines.append(line)
    }

    func finish(result: CommandRunner.Result) {
        exitCode = result.exitCode
        phase = result.didSucceed ? .succeeded : .failed
    }
}
