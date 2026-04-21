import AppKit
import SwiftUI
import TermQCore

struct DiagnosticsView: View {
    @ObservedObject private var buffer = TermQLogBuffer.shared
    @State private var selectedCategory = "all"
    @State private var selectedLevel: DiagnosticsLevel = .notice
    @State private var searchText = ""
    @State private var isAtBottom = true
    @State private var expandedIDs: Set<UUID> = []

    private let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        return fmt
    }()

    private var availableCategories: [String] {
        let fromEntries = Set(buffer.entries.map(\.category)).sorted()
        return fromEntries
    }

    private var filteredEntries: [LogEntry] {
        buffer.entries.filter { entry in
            (selectedCategory == "all" || entry.category == selectedCategory)
                && entry.level >= selectedLevel
                && (searchText.isEmpty || entry.message.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            logList
            Divider()
            statusBar
        }
        .frame(minWidth: 700, minHeight: 400)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker(Strings.Diagnostics.filterCategory, selection: $selectedCategory) {
                Text(Strings.Diagnostics.filterCategoryAll).tag("all")
                if !availableCategories.isEmpty {
                    Divider()
                    ForEach(availableCategories, id: \.self) { cat in
                        Text(cat).tag(cat)
                    }
                }
            }
            .frame(width: 140)
            .onChange(of: selectedCategory) { isAtBottom = true }

            Picker(Strings.Diagnostics.filterLevel, selection: $selectedLevel) {
                ForEach(DiagnosticsLevel.allCases, id: \.self) { level in
                    Text(level.filterLabel).tag(level)
                }
            }
            .frame(width: 120)
            .onChange(of: selectedLevel) { isAtBottom = true }

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(Strings.Diagnostics.searchPlaceholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { isAtBottom = true }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Spacer()

            Button(Strings.Diagnostics.clear) {
                buffer.clear()
                expandedIDs.removeAll()
            }

            Button(Strings.Diagnostics.export) {
                if NSEvent.modifierFlags.contains(.option) {
                    copyReportToClipboard()
                } else {
                    showExportPanel()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Log List

    private var logList: some View {
        ScrollViewReader { proxy in
            List(filteredEntries) { entry in
                entryRow(entry)
                    .onAppear {
                        if entry.id == filteredEntries.last?.id {
                            isAtBottom = true
                        }
                    }
                    .onDisappear {
                        if entry.id == filteredEntries.last?.id {
                            isAtBottom = false
                        }
                    }
                    .id(entry.id)
            }
            .listStyle(.plain)
            .onChange(of: buffer.entries.count) {
                if isAtBottom, let last = filteredEntries.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .overlay(alignment: .bottom) {
                if !isAtBottom {
                    Button {
                        if let last = filteredEntries.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                        isAtBottom = true
                    } label: {
                        Label(Strings.Diagnostics.jumpToLatest, systemImage: "chevron.down")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                    .shadow(radius: 2)
                }
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: LogEntry) -> some View {
        let isMultiline = entry.message.contains("\n")
        let isExpanded = expandedIDs.contains(entry.id)
        let lines = entry.message.components(separatedBy: "\n")
        let firstLine = lines.first ?? entry.message

        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dateFormatter.string(from: entry.date))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .leading)

                Text(entry.level.label)
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundStyle(entry.level.color)
                    .frame(width: 60, alignment: .leading)

                Text(entry.category)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)

                Text(firstLine)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)

                Spacer()

                if isMultiline {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if isMultiline && isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.dropFirst().enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 282)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isMultiline else { return }
            if isExpanded {
                expandedIDs.remove(entry.id)
            } else {
                expandedIDs.insert(entry.id)
            }
        }
        .padding(.vertical, 1)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            let total = buffer.entries.count
            let matching = filteredEntries.count

            Text(Strings.Diagnostics.statusEntries(total, matching))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("·")
                .foregroundStyle(.secondary)
                .font(.caption)

            HStack(spacing: 4) {
                Circle()
                    .fill(isAtBottom ? Color.green : Color.secondary)
                    .frame(width: 6, height: 6)
                Text(isAtBottom ? Strings.Diagnostics.statusLive : Strings.Diagnostics.statusPaused)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle(isOn: $buffer.verboseMode) {
                Text(Strings.Diagnostics.verboseMode)
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .help(Strings.Diagnostics.verboseModeHelp)

            if buffer.verboseMode {
                Text(Strings.Diagnostics.verboseWarning)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Export

    private func buildReport() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let osInfo = ProcessInfo.processInfo.operatingSystemVersionString
        let generated = ISO8601DateFormatter().string(from: Date())
        let filterDesc = [
            selectedCategory == "all" ? nil : "category=\(selectedCategory)",
            "level=\(selectedLevel.rawValue)+",
            searchText.isEmpty ? nil : "search=\(searchText)",
        ].compactMap { $0 }.joined(separator: ", ")

        var lines: [String] = [
            Strings.Diagnostics.exportTitle,
            String(repeating: "═", count: 40),
            "App Version:  \(version) (build \(build))",
            "macOS:        \(osInfo)",
            "Generated:    \(generated)",
            "Entries:      \(buffer.entries.count) total / \(filteredEntries.count) matching current filter",
            "Filter:       \(filterDesc)",
            "",
            String(repeating: "─", count: 40),
        ]

        let exportFormatter = DateFormatter()
        exportFormatter.dateFormat = "HH:mm:ss.SSS"

        for entry in filteredEntries {
            let ts = exportFormatter.string(from: entry.date)
            let entryLines = entry.message.components(separatedBy: "\n")
            let first = entryLines[0]
            let levelCol = entry.level.label.padding(toLength: 8, withPad: " ", startingAt: 0)
            let catCol = entry.category.padding(toLength: 8, withPad: " ", startingAt: 0)
            lines.append("\(ts)  \(levelCol)  \(catCol)  \(first)")
            for continuation in entryLines.dropFirst() {
                lines.append(String(repeating: " ", count: 30) + continuation)
            }
        }

        lines += [String(repeating: "─", count: 40), "", Strings.Diagnostics.exportFooter]
        return lines.joined(separator: "\n")
    }

    private func showExportPanel() {
        let report = buildReport()
        let panel = NSSavePanel()
        let dateStr = DateFormatter().string(from: Date())
        panel.nameFieldStringValue = "TermQ Diagnostics \(dateStr).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }

    private func copyReportToClipboard() {
        let report = buildReport()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
}
