import SwiftUI

// MARK: - Help Topic Model

struct HelpTopicMetadata: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let keywords: [String]

    func matches(_ query: String) -> Bool {
        let lowercasedQuery = query.lowercased()
        return title.lowercased().contains(lowercasedQuery)
            || keywords.contains { $0.lowercased().contains(lowercasedQuery) }
    }

    static func == (lhs: HelpTopicMetadata, rhs: HelpTopicMetadata) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct HelpIndex: Codable {
    let topics: [HelpTopicMetadata]
}

// MARK: - Help Content Loader

enum HelpContentLoader {
    /// The bundle containing help resources
    /// Checks Contents/Resources first (for signed/installed app), then falls back to Bundle.module
    fileprivate static let resourceBundle: Bundle = {
        // First, try the explicit path where the resource bundle is copied during release
        if let resourcesPath = Bundle.main.resourceURL?
            .appendingPathComponent("TermQ_TermQ.bundle").path,
            let bundle = Bundle(path: resourcesPath)
        {
            return bundle
        }
        // Fall back to Bundle.module for development/SPM builds
        #if SWIFT_PACKAGE
            return Bundle.module
        #else
            return Bundle.main
        #endif
    }()

    /// Load the help index from bundle
    static func loadIndex() -> [HelpTopicMetadata] {
        guard let url = resourceBundle.url(forResource: "index", withExtension: "json", subdirectory: "Help"),
            let data = try? Data(contentsOf: url),
            let index = try? JSONDecoder().decode(HelpIndex.self, from: data)
        else {
            print("Failed to load help index from bundle")
            return []
        }
        return index.topics
    }

    /// Load markdown content for a topic
    static func loadContent(for topicId: String) -> String {
        guard let url = resourceBundle.url(forResource: topicId, withExtension: "md", subdirectory: "Help"),
            let content = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "Content not found for topic: \(topicId)"
        }
        return content
    }

    /// Load an image from the Help/Images folder
    static func loadImage(named name: String) -> NSImage? {
        // Try Help/Images first
        if let url = resourceBundle.url(
            forResource: name, withExtension: nil, subdirectory: "Help/Images")
        {
            return NSImage(contentsOf: url)
        }
        return nil
    }
}

// MARK: - Help View

struct HelpView: View {
    @State private var searchText = ""
    @State private var selectedTopic: HelpTopicMetadata?
    @State private var topics: [HelpTopicMetadata] = []

    private var filteredTopics: [HelpTopicMetadata] {
        if searchText.isEmpty {
            return topics
        }
        return topics.filter { $0.matches(searchText) }
    }

    var body: some View {
        NavigationSplitView {
            List(filteredTopics, selection: $selectedTopic) { topic in
                HelpTopicRow(topic: topic)
                    .tag(topic)
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, prompt: Strings.Help.searchPlaceholder)
            .frame(minWidth: 200)
        } detail: {
            if let topic = selectedTopic {
                HelpDetailView(topic: topic)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(Strings.Help.title)
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(Strings.Help.searchPlaceholder)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            topics = HelpContentLoader.loadIndex()
            if selectedTopic == nil {
                selectedTopic = topics.first
            }
        }
    }
}

// MARK: - Help Topic Row

private struct HelpTopicRow: View {
    let topic: HelpTopicMetadata

    var body: some View {
        Label {
            Text(topic.title)
        } icon: {
            Image(systemName: topic.icon)
                .foregroundColor(.accentColor)
        }
    }
}

// MARK: - Help Detail View

private struct HelpDetailView: View {
    let topic: HelpTopicMetadata
    @State private var content: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: topic.icon)
                        .font(.title)
                        .foregroundColor(.accentColor)
                    Text(topic.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                .padding(.bottom, 8)

                Divider()

                // Content - render markdown
                MarkdownContentView(markdown: content)

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            content = HelpContentLoader.loadContent(for: topic.id)
        }
        .onChange(of: topic.id) { _, newId in
            content = HelpContentLoader.loadContent(for: newId)
        }
    }
}

// MARK: - Markdown Content View

private struct MarkdownContentView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(parseMarkdown().enumerated()), id: \.offset) { _, element in
                element
            }
        }
        .textSelection(.enabled)
    }

    private func parseMarkdown() -> [AnyView] {
        var views: [AnyView] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Skip the title (first H1) since we show it in the header
            if line.hasPrefix("# ") && views.isEmpty {
                i += 1
                continue
            }

            // H2 headers
            if line.hasPrefix("## ") {
                let text = String(line.dropFirst(3))
                views.append(
                    AnyView(
                        Text(text)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding(.top, 8)
                    ))
                i += 1
                continue
            }

            // H3 headers
            if line.hasPrefix("### ") {
                let text = String(line.dropFirst(4))
                views.append(
                    AnyView(
                        Text(text)
                            .font(.title3)
                            .fontWeight(.medium)
                            .padding(.top, 4)
                    ))
                i += 1
                continue
            }

            // Images
            if line.contains("![") && line.contains("](") {
                if let imageView = parseImageLine(line) {
                    views.append(imageView)
                }
                i += 1
                continue
            }

            // Code blocks
            if line.hasPrefix("```") {
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                let code = codeLines.joined(separator: "\n")
                views.append(
                    AnyView(
                        Text(code)
                            .font(.system(.body, design: .monospaced))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    ))
                i += 1
                continue
            }

            // Tables
            if line.contains("|") && i + 1 < lines.count && lines[i + 1].contains("---") {
                var tableLines: [String] = [line]
                i += 1
                while i < lines.count && lines[i].contains("|") {
                    tableLines.append(lines[i])
                    i += 1
                }
                views.append(parseTable(tableLines))
                continue
            }

            // Bullet points
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let text = String(line.dropFirst(2))
                views.append(
                    AnyView(
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                            Text(parseInlineMarkdown(text))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ))
                i += 1
                continue
            }

            // Numbered list
            if let match = line.wholeMatch(of: #/^(\d+)\.\s+(.+)/#) {
                let text = String(match.2)
                let number = String(match.1)
                views.append(
                    AnyView(
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(number).")
                                .frame(width: 20, alignment: .trailing)
                            Text(parseInlineMarkdown(text))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ))
                i += 1
                continue
            }

            // Regular paragraph
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                views.append(
                    AnyView(
                        Text(parseInlineMarkdown(line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    ))
            }

            i += 1
        }

        return views
    }

    private func parseImageLine(_ line: String) -> AnyView? {
        // Parse ![alt](path)
        guard let altStart = line.firstIndex(of: "["),
            let altEnd = line.firstIndex(of: "]"),
            let pathStart = line.firstIndex(of: "("),
            let pathEnd = line.lastIndex(of: ")")
        else {
            return nil
        }

        let altText = String(line[line.index(after: altStart)..<altEnd])
        var path = String(line[line.index(after: pathStart)..<pathEnd])

        // Handle relative paths like ../Images/foo.png
        if path.hasPrefix("../Images/") {
            path = String(path.dropFirst(10))  // Remove ../Images/
        } else if path.hasPrefix("Images/") {
            path = String(path.dropFirst(7))  // Remove Images/
        }

        // Try to load the image
        let imageName = (path as NSString).deletingPathExtension
        let imageExt = (path as NSString).pathExtension

        // Use HelpContentLoader's resource bundle
        if let url = HelpContentLoader.resourceBundle.url(
            forResource: imageName, withExtension: imageExt, subdirectory: "Help/Images"),
            let nsImage = NSImage(contentsOf: url)
        {
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 500)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    if !altText.isEmpty {
                        Text(altText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            )
        }

        // Image not found - show placeholder
        return AnyView(
            Text("[\(altText)]")
                .foregroundColor(.secondary)
                .italic()
        )
    }

    private func parseTable(_ lines: [String]) -> AnyView {
        guard lines.count >= 2 else { return AnyView(EmptyView()) }

        // Parse header
        let headerCells =
            lines[0]
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Skip separator line (index 1)

        // Parse body rows
        var bodyRows: [[String]] = []
        for i in 2..<lines.count {
            let cells =
                lines[i]
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !cells.isEmpty {
                bodyRows.append(cells)
            }
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(Array(headerCells.enumerated()), id: \.offset) { _, cell in
                        Text(parseInlineMarkdown(cell))
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                }
                .background(Color.secondary.opacity(0.1))

                Divider()

                // Body rows
                ForEach(Array(bodyRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(parseInlineMarkdown(cell))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                    }
                    Divider()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .padding(.vertical, 8)
        )
    }

    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        // Use SwiftUI's built-in markdown parsing for inline elements
        // This handles **bold**, *italic*, `code`, and [links](url)
        do {
            return try AttributedString(markdown: text)
        } catch {
            return AttributedString(text)
        }
    }
}

// MARK: - Help Window

struct HelpWindowView: View {
    var body: some View {
        HelpView()
    }
}
