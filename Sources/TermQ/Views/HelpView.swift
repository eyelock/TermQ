import SwiftUI

// MARK: - Help Topic Model

struct HelpTopic: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let icon: String
    let content: String
    let keywords: [String]

    func matches(_ query: String) -> Bool {
        let lowercasedQuery = query.lowercased()
        return title.lowercased().contains(lowercasedQuery)
            || content.lowercased().contains(lowercasedQuery)
            || keywords.contains { $0.lowercased().contains(lowercasedQuery) }
    }

    static func == (lhs: HelpTopic, rhs: HelpTopic) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Help Content

enum HelpContent {
    static let topics: [HelpTopic] = [
        HelpTopic(
            title: "Getting Started",
            icon: "star",
            content: """
                Welcome to TermQ - a Kanban-style terminal queue manager for macOS.

                **Quick Start:**
                1. Click the **+** button in the toolbar to add a new terminal or column
                2. Click on a terminal card to open it in full view
                3. Drag cards between columns to organize your workflow
                4. Pin frequently-used terminals with the ⭐ button for quick access

                TermQ helps you organize multiple terminal sessions in a visual board layout, so you never lose track of your running tasks.
                """,
            keywords: ["start", "begin", "intro", "introduction", "overview", "welcome"]
        ),

        HelpTopic(
            title: "Keyboard Shortcuts",
            icon: "keyboard",
            content: """
                **Terminal Management:**
                • **⌘T** - Quick new terminal (same column and working directory)
                • **⌘N** - New terminal with dialog
                • **⌘⇧N** - New column

                **Navigation:**
                • **⌘B** - Back to board (close terminal view)
                • **⌘]** - Next pinned terminal
                • **⌘[** - Previous pinned terminal

                **Actions:**
                • **⌘D** - Toggle pin on current terminal
                """,
            keywords: ["shortcut", "keyboard", "hotkey", "key", "command", "ctrl", "cmd"]
        ),

        HelpTopic(
            title: "Working with Terminals",
            icon: "terminal",
            content: """
                **Creating Terminals:**
                • Click **Add Terminal** at the bottom of any column
                • Use **⌘N** for the new terminal dialog
                • Use **⌘T** for a quick terminal in the same column

                **Terminal Cards:**
                Each terminal card shows:
                • Title and description
                • Tags (key=value pairs)
                • Working directory
                • Running status (green dot)
                • Pin status (star icon)

                **Context Menu:**
                Right-click any terminal card for options:
                • Open Terminal
                • Edit Details
                • Pin/Unpin
                • Delete

                **Native Terminal:**
                Click the Terminal button in the toolbar to open macOS Terminal.app at the current working directory.
                """,
            keywords: ["terminal", "card", "create", "new", "session", "shell", "native", "Terminal.app"]
        ),

        HelpTopic(
            title: "Pinned Terminals & Tabs",
            icon: "star.fill",
            content: """
                **Pinning Terminals:**
                Pin frequently-used terminals to access them quickly via tabs.

                • Click the ⭐ button on a card or in the toolbar
                • Use **⌘D** to toggle pin status
                • Pinned terminals appear as tabs at the top of the focused view

                **Tab Navigation:**
                • Click a tab to switch to that terminal
                • Use **⌘]** and **⌘[** to cycle through pinned terminals
                • Hover over a tab to see Edit and Delete buttons

                **Smart Behavior:**
                • Creating a new terminal while focused auto-pins it
                • The current terminal always shows as a tab (even if not pinned)
                • Deleting a tab focuses the adjacent tab instead of returning to board
                """,
            keywords: ["pin", "tab", "favorite", "star", "quick", "access"]
        ),

        HelpTopic(
            title: "Columns & Organization",
            icon: "rectangle.split.3x1",
            content: """
                **Managing Columns:**
                • Click **⌘⇧N** or use the + menu to add a new column
                • Click the **⋯** menu on a column header for options
                • Rename columns to match your workflow
                • Delete empty columns (move terminals first)

                **Drag & Drop:**
                • Drag terminal cards between columns to reorganize
                • Cards show a highlight when hovering over a valid drop target

                **Suggested Workflows:**
                • **To Do / In Progress / Done** - Track task status
                • **Dev / Staging / Prod** - Organize by environment
                • **Project A / Project B** - Group by project
                """,
            keywords: ["column", "organize", "drag", "drop", "move", "workflow", "kanban"]
        ),

        HelpTopic(
            title: "CLI Tool",
            icon: "apple.terminal",
            content: """
                **Installation:**
                The `termq` CLI tool lets you open terminals from your shell.

                ```
                # Install after building
                make install

                # Or manually copy
                cp .build/release/termq /usr/local/bin/
                ```

                **Usage Examples:**
                ```
                # Open in current directory
                termq open

                # Open with name and description
                termq open --name "API Server" --description "Backend"

                # Open in specific column
                termq open --column "In Progress"

                # Open with tags
                termq open --name "Build" --tag env=prod --tag version=1.0

                # Open in specific directory
                termq open --path /path/to/project
                ```
                """,
            keywords: ["cli", "command", "line", "terminal", "shell", "install", "termq"]
        ),

        HelpTopic(
            title: "Configuration & Data",
            icon: "gearshape",
            content: """
                **Data Storage:**
                TermQ stores its data at:
                ```
                ~/Library/Application Support/TermQ/board.json
                ```

                This JSON file contains all columns, cards, and their metadata. You can:
                • Back it up manually
                • Edit it with a text editor (when app is closed)
                • Sync it via cloud storage

                **Settings:**
                Access Settings via **⌘,** or the TermQ menu.

                **CLI Installation:**
                The Settings window shows CLI tool status and provides install/uninstall options.
                """,
            keywords: ["config", "settings", "data", "storage", "json", "backup", "preferences"]
        ),

        HelpTopic(
            title: "Tips & Tricks",
            icon: "lightbulb",
            content: """
                **Productivity Tips:**

                • **Quick Terminal (⌘T)** creates a terminal with the same working directory as the current one - great for parallel tasks

                • **Pin your most-used terminals** to quickly switch between them with ⌘] and ⌘[

                • **Use tags** to add metadata like `env=prod` or `project=api` for easy identification

                • **Columns auto-expand** to fill the window - resize the window to fit more columns

                • **Right-click cards** for quick access to edit, delete, and pin options

                • **Tab hover actions** let you edit or close terminals without switching to them first

                • **Open in Terminal.app** - Click the Terminal button to open the current directory in native macOS Terminal
                """,
            keywords: ["tip", "trick", "productivity", "efficient", "workflow", "advice", "native"]
        ),

        HelpTopic(
            title: "About TermQ",
            icon: "info.circle",
            content: """
                **TermQ** - Kanban-style Terminal Queue Manager

                A macOS application for organizing multiple terminal sessions in a visual board layout.

                **Features:**
                • Kanban board layout with customizable columns
                • Persistent terminal sessions
                • Pinned terminals with tab navigation
                • Native Terminal.app integration
                • Rich metadata (titles, descriptions, tags)
                • Drag & drop organization
                • CLI tool for shell integration
                • Keyboard shortcuts for power users

                **Requirements:**
                • macOS 14.0 (Sonoma) or later

                **License:**
                MIT License

                **Source Code:**
                https://github.com/eyelock/TermQ
                """,
            keywords: ["about", "info", "version", "license", "credit", "github"]
        ),
    ]
}

// MARK: - Help View

struct HelpView: View {
    @State private var searchText = ""
    @State private var selectedTopic: HelpTopic?

    private var filteredTopics: [HelpTopic] {
        if searchText.isEmpty {
            return HelpContent.topics
        }
        return HelpContent.topics.filter { $0.matches(searchText) }
    }

    var body: some View {
        NavigationSplitView {
            List(filteredTopics, selection: $selectedTopic) { topic in
                HelpTopicRow(topic: topic)
                    .tag(topic)
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, prompt: "Search help topics")
            .frame(minWidth: 200)
        } detail: {
            if let topic = selectedTopic {
                HelpDetailView(topic: topic)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a topic")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Choose a help topic from the sidebar or search for specific information.")
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
            // Select first topic by default
            if selectedTopic == nil {
                selectedTopic = HelpContent.topics.first
            }
        }
    }
}

// MARK: - Help Topic Row

private struct HelpTopicRow: View {
    let topic: HelpTopic

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
    let topic: HelpTopic

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

                // Content
                Text(LocalizedStringKey(topic.content))
                    .font(.body)
                    .textSelection(.enabled)

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Help Window

struct HelpWindowView: View {
    var body: some View {
        HelpView()
    }
}
