import AppKit
import SwiftTerm
import TermQCore

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
        setupTerminalView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupTerminalView() {
        guard let terminal = TerminalSessionManager.shared.getTerminalView(for: cardId, paneId: paneId) else {
            return
        }

        self.terminalView = terminal

        let theme = TerminalSessionManager.shared.currentTheme
        layer?.backgroundColor = theme.background.cgColor

        // Terminal is inset 5pt from the pane edge — provides breathing room between
        // the pane boundary (where the separator/focus lines are drawn by the overlay)
        // and the terminal content. layer.backgroundColor fills this gap with the
        // terminal background colour so the padding is visually seamless.
        let inset: CGFloat = 5
        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)

        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
        ])
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
