import AppKit
import SwiftTerm
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
    var terminalView: TerminalView?
    var isActivePan: Bool = false
    var onFocus: (() -> Void)?

    init(cardId: UUID, paneId: String) {
        self.cardId = cardId
        self.paneId = paneId
        super.init(frame: .zero)

        wantsLayer = true
        layer?.borderWidth = 2
        setupTerminalView()
        updateBorder()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupTerminalView() {
        guard let terminal = TerminalSessionManager.shared.getTerminalView(for: cardId, paneId: paneId) else {
            return
        }

        self.terminalView = terminal

        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)

        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: topAnchor),
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func updateBorder() {
        if isActivePan {
            layer?.borderColor = NSColor.systemBlue.cgColor
        } else {
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let target = super.hitTest(point)
        if !isActivePan,
            target != nil,
            target === terminalView || target?.isDescendant(of: terminalView ?? self) == true
        {
            onFocus?()
        }
        return target
    }
}
