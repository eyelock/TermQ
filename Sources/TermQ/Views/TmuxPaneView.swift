import SwiftUI
import TermQCore

/// View for rendering a single tmux pane's content
public struct TmuxPaneView: View {
    let pane: TmuxPane
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var content: AttributedString = AttributedString("")

    public init(pane: TmuxPane, isSelected: Bool = false, onSelect: @escaping () -> Void = {}) {
        self.pane = pane
        self.isSelected = isSelected
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Pane header
            HStack {
                if pane.isActive {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption2)
                }

                Text(pane.title.isEmpty ? "Pane \(pane.id)" : pane.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                if pane.inCopyMode {
                    Text("COPY")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.3))
                        .cornerRadius(3)
                }

                Text("\(pane.width)×\(pane.height)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))

            // Pane content area
            ScrollView([.horizontal, .vertical]) {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(4)
            }
            .background(Color(nsColor: .textBackgroundColor))

            // Path indicator
            if !pane.currentPath.isEmpty {
                HStack {
                    Image(systemName: "folder")
                        .font(.caption2)
                    Text(pane.currentPath)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.05))
            }
        }
        .border(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), width: isSelected ? 2 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    /// Update content from control mode output
    public mutating func updateContent(_ text: String) {
        content = AttributedString(text)
    }
}

/// View for rendering tmux panes in a layout
public struct TmuxLayoutView: View {
    @ObservedObject var parser: TmuxControlModeParser
    @Binding var selectedPaneId: String?
    let onPaneSelect: (String) -> Void

    public init(
        parser: TmuxControlModeParser,
        selectedPaneId: Binding<String?>,
        onPaneSelect: @escaping (String) -> Void = { _ in }
    ) {
        self.parser = parser
        self._selectedPaneId = selectedPaneId
        self.onPaneSelect = onPaneSelect
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(parser.panes) { pane in
                    let frame = calculatePaneFrame(pane: pane, in: geometry.size)

                    TmuxPaneView(
                        pane: pane,
                        isSelected: selectedPaneId == pane.id,
                        onSelect: {
                            selectedPaneId = pane.id
                            onPaneSelect(pane.id)
                        }
                    )
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
    }

    /// Calculate the frame for a pane based on its tmux coordinates
    private func calculatePaneFrame(pane: TmuxPane, in size: CGSize) -> CGRect {
        // Find the total dimensions from all panes
        let maxWidth = parser.panes.map { $0.x + $0.width }.max() ?? 1
        let maxHeight = parser.panes.map { $0.y + $0.height }.max() ?? 1

        // Scale factor to fit in the available space
        let scaleX = size.width / CGFloat(maxWidth)
        let scaleY = size.height / CGFloat(maxHeight)

        let x = CGFloat(pane.x) * scaleX
        let y = CGFloat(pane.y) * scaleY
        let width = CGFloat(pane.width) * scaleX
        let height = CGFloat(pane.height) * scaleY

        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Window tab view for tmux windows
public struct TmuxWindowTabView: View {
    let window: TmuxWindow
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    public init(
        window: TmuxWindow,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.window = window
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onClose = onClose
    }

    public var body: some View {
        HStack(spacing: 4) {
            if window.isActive {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            }

            Text(window.name)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .opacity(isSelected ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

/// Main control mode terminal view
public struct TmuxControlModeView: View {
    @StateObject private var session: TmuxControlModeSession
    @State private var selectedPaneId: String?
    @State private var selectedWindowId: String?
    @State private var isConnected = false
    @State private var errorMessage: String?

    private let sessionName: String

    public init(sessionName: String) {
        self.sessionName = sessionName
        _session = StateObject(wrappedValue: TmuxControlModeSession(sessionName: sessionName))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Window tabs
            if !session.parser.windows.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(session.parser.windows) { window in
                            TmuxWindowTabView(
                                window: window,
                                isSelected: selectedWindowId == window.id,
                                onSelect: {
                                    selectedWindowId = window.id
                                    selectWindow(window.id)
                                },
                                onClose: {
                                    closeWindow(window.id)
                                }
                            )
                        }

                        // New window button
                        Button(action: createNewWindow) {
                            Image(systemName: "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 28)
                .background(Color.secondary.opacity(0.1))
            }

            // Pane layout
            if isConnected {
                TmuxLayoutView(
                    parser: session.parser,
                    selectedPaneId: $selectedPaneId,
                    onPaneSelect: { paneId in
                        selectPane(paneId)
                    }
                )
            } else {
                VStack(spacing: 16) {
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }

                    Button("Connect to Control Mode") {
                        connect()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Toolbar
            HStack {
                Button(action: { session.splitHorizontal() }) {
                    Image(systemName: "rectangle.split.1x2")
                }
                .help("Split Horizontal")

                Button(action: { session.splitVertical() }) {
                    Image(systemName: "rectangle.split.2x1")
                }
                .help("Split Vertical")

                Divider()
                    .frame(height: 16)

                Button(action: { session.selectPane(direction: .up) }) {
                    Image(systemName: "arrow.up")
                }
                .help("Select Pane Above")

                Button(action: { session.selectPane(direction: .down) }) {
                    Image(systemName: "arrow.down")
                }
                .help("Select Pane Below")

                Button(action: { session.selectPane(direction: .left) }) {
                    Image(systemName: "arrow.left")
                }
                .help("Select Pane Left")

                Button(action: { session.selectPane(direction: .right) }) {
                    Image(systemName: "arrow.right")
                }
                .help("Select Pane Right")

                Spacer()

                if isConnected {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Connected")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.05))
        }
        .onAppear {
            connect()
        }
        .onDisappear {
            session.disconnect()
        }
    }

    private func connect() {
        Task {
            do {
                try await session.connect()
                isConnected = true
                errorMessage = nil
            } catch {
                errorMessage = "Failed to connect: \(error.localizedDescription)"
                isConnected = false
            }
        }
    }

    private func selectPane(_ paneId: String) {
        session.sendCommand("select-pane -t %\(paneId)")
    }

    private func selectWindow(_ windowId: String) {
        session.sendCommand("select-window -t @\(windowId)")
    }

    private func closeWindow(_ windowId: String) {
        session.sendCommand("kill-window -t @\(windowId)")
    }

    private func createNewWindow() {
        session.sendCommand("new-window")
    }
}

// MARK: - Preview

#if DEBUG
struct TmuxPaneView_Previews: PreviewProvider {
    static var previews: some View {
        TmuxPaneView(
            pane: TmuxPane(id: "0", windowId: "0", width: 80, height: 24, x: 0, y: 0),
            isSelected: true
        )
        .frame(width: 400, height: 300)
    }
}
#endif
