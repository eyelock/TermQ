import AppKit
import SwiftUI
import TermQCore

/// SwiftUI wrapper for a pane-specific terminal view with input routing
///
/// This view wraps a TermQTerminalView for a specific tmux pane and handles:
/// - Input routing to the active pane via control mode
/// - Click-to-focus behavior
/// - Visual indication of active/inactive state
struct PaneTerminalView: NSViewRepresentable {
    let cardId: UUID
    let paneId: String
    let isActive: Bool
    let onFocus: () -> Void

    func makeNSView(context: Context) -> PaneTerminalViewNSView {
        let view = PaneTerminalViewNSView(cardId: cardId, paneId: paneId)
        view.onFocus = onFocus
        return view
    }

    func updateNSView(_ nsView: PaneTerminalViewNSView, context: Context) {
        nsView.isActivePan = isActive
        nsView.updateBorder()
    }
}

/// NSView container for pane terminal with input routing
class PaneTerminalViewNSView: NSView {
    let cardId: UUID
    let paneId: String
    var terminalView: TermQTerminalView?
    var isActivePan: Bool = false
    var onFocus: (() -> Void)?

    private var borderView: NSView?

    init(cardId: UUID, paneId: String) {
        self.cardId = cardId
        self.paneId = paneId
        super.init(frame: .zero)

        setupTerminalView()
        setupBorder()
        setupClickTracking()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupTerminalView() {
        // Get the terminal view from session manager
        guard let terminal = TerminalSessionManager.shared.getTerminalView(for: cardId, paneId: paneId) else {
            return
        }

        self.terminalView = terminal

        // Add terminal view as subview
        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)

        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: topAnchor),
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func setupBorder() {
        let border = NSView()
        border.wantsLayer = true
        border.layer?.borderWidth = 2
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border, positioned: .above, relativeTo: terminalView)

        NSLayoutConstraint.activate([
            border.topAnchor.constraint(equalTo: topAnchor),
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        borderView = border
        updateBorder()
    }

    func updateBorder() {
        guard let border = borderView else { return }

        if isActivePan {
            border.layer?.borderColor = NSColor.systemBlue.cgColor
        } else {
            border.layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    private func setupClickTracking() {
        // Add click gesture to focus this pane
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(clickGesture)
    }

    @objc private func handleClick() {
        onFocus?()

        // Make this terminal first responder for keyboard input
        window?.makeFirstResponder(terminalView)
    }

    // Override acceptsFirstResponder to allow keyboard focus
    override var acceptsFirstResponder: Bool {
        return true
    }

    // Override becomeFirstResponder to route input when this pane becomes active
    override func becomeFirstResponder() -> Bool {
        // Update active pane in session for input routing
        TerminalSessionManager.shared.setActivePane(cardId: cardId, paneId: paneId)

        return super.becomeFirstResponder()
    }

    // Override keyDown to route keyboard input through control mode
    override func keyDown(with event: NSEvent) {
        guard let controlSession = TerminalSessionManager.shared.getControlModeSession(for: cardId) else {
            // Fallback to normal terminal input if control mode not available
            super.keyDown(with: event)
            return
        }

        // Convert key event to data and send through control mode
        // Tmux will route the input to the active pane
        if let characters = event.characters {
            if let data = characters.data(using: .utf8) {
                controlSession.sendInput(data)
            }
        }
    }
}
