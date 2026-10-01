import AppKit
import SwiftUI

/// Small panel behind Help → Memory Report…: collects a `MemoryReport`, then offers
/// to save or copy it. Each time it is opened (and not already collecting) a fresh
/// report is generated.
@MainActor
final class MemoryReportWindowController: NSWindowController, NSWindowDelegate {
    static let shared = MemoryReportWindowController()

    private let model = MemoryReportModel()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = Strings.MemoryReport.windowTitle
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: MemoryReportView(model: model))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.startIfIdle()
    }

    func windowWillClose(_ notification: Notification) {
        model.reset()
    }
}

@MainActor
@Observable
final class MemoryReportModel {
    enum Phase {
        case idle
        case collecting(MemoryReportCollector.Step)
        case ready(report: String, snapshot: MemoryReport.Snapshot)
    }

    private(set) var phase: Phase = .idle
    private(set) var didCopy = false
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Identifies the current run so a cancelled run's late callbacks are ignored.
    @ObservationIgnored private var generation = 0

    func startIfIdle() {
        guard case .idle = phase else { return }
        generation += 1
        let run = generation
        didCopy = false
        phase = .collecting(.inProcess)
        task = Task { [weak self] in
            let snapshot = await MemoryReportCollector.collect { step in
                guard let self, self.generation == run else { return }
                self.phase = .collecting(step)
            }
            guard let self, self.generation == run, !Task.isCancelled else { return }
            self.phase = .ready(report: MemoryReport.render(snapshot), snapshot: snapshot)
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        generation += 1
        phase = .idle
        didCopy = false
    }

    func copy(_ report: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        didCopy = true
    }

    func save(_ report: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "TermQ Memory Report \(formatter.string(from: Date())).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // The error text can include the chosen path, which is user data.
            TermQLogger.ui.error("Memory report: save failed")
        }
    }
}

struct MemoryReportView: View {
    let model: MemoryReportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.phase {
            case .idle, .collecting:
                collecting
            case .ready(let report, let snapshot):
                ready(report: report, snapshot: snapshot)
            }
        }
        .padding(20)
        .frame(width: 480, alignment: .leading)
    }

    private var collecting: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(stepText).font(.headline)
            }
            Text(Strings.MemoryReport.pauseNotice)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stepText: String {
        guard case .collecting(let step) = model.phase else { return Strings.MemoryReport.collecting }
        switch step {
        case .inProcess, .footprint: return Strings.MemoryReport.collecting
        case .heap, .leaks: return Strings.MemoryReport.analysing
        }
    }

    private func ready(report: String, snapshot: MemoryReport.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.MemoryReport.ready).font(.headline)
            Text(summary(snapshot))
                .font(.callout)
                .textSelection(.enabled)
            Text(Strings.MemoryReport.privacyNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(model.didCopy ? Strings.MemoryReport.copied : Strings.MemoryReport.copy) {
                    model.copy(report)
                }
                Button(Strings.MemoryReport.save) {
                    model.save(report)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func summary(_ snapshot: MemoryReport.Snapshot) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        let unknown = "?"
        return Strings.MemoryReport.summary(
            snapshot.footprintBytes.map { formatter.string(fromByteCount: Int64($0)) } ?? unknown,
            snapshot.peakFootprintBytes.map { formatter.string(fromByteCount: Int64($0)) } ?? unknown,
            snapshot.sessions.count
        )
    }
}
