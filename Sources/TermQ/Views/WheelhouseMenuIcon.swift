import Foundation

/// One SF Symbol per Wheelhouse menu action, so an action looks the same in
/// every menu it appears in (sidebar row, stage chip, pane header, inbox).
/// Where the Repositories tab has the same kind of action, it uses the same
/// symbol.
enum WheelhouseMenuIcon {
    /// Start the seat (Repositories: Launch harness).
    static let openTerminal = "play.fill"
    static let showTerminal = "macwindow"
    static let birth = "sparkles"
    /// Install a seat's harness (the same arrow Repositories uses to bring
    /// something down).
    static let install = "arrow.down.circle"
    static let actionRequired = "exclamationmark.triangle.fill"
    static let wakeFocus = "sunrise"
    static let focus = "scope"
    static let handoff = "moon.zzz"
    static let closeTerminal = "xmark.octagon"
    /// Repositories: New Terminal.
    static let quickTerminal = "terminal"
    /// Repositories: harness items.
    static let harnessDetails = "puzzlepiece.extension"
    static let pin = "pin"
    static let pinned = "pin.fill"
    /// Repositories: Copy Pathname.
    static let copy = "doc.on.clipboard"
    /// Repositories: Reveal in Finder.
    static let revealInFinder = "folder"
    static let sendToSeat = "paperplane"
    static let comment = "text.bubble"
    static let closeBead = "checkmark.circle"
    /// Repositories: Open on remote.
    static let openLink = "network"
    static let wheelhouse = "steeringwheel"
    static let allWheelhouses = "square.grid.2x2"
    /// The board's Zoom.
    static let zoom = "arrow.up.left.and.arrow.down.right"
    static let exitZoom = "arrow.down.right.and.arrow.up.left"
    /// Repositories: New Worktree.
    static let add = "plus"

    /// A harness focus: the wake focus has its own symbol, the rest share one.
    static func focus(named name: String) -> String {
        name == "wake" ? wakeFocus : focus
    }
}
