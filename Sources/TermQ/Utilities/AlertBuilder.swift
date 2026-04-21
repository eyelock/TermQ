import AppKit

/// Utility for constructing and running NSAlert dialogs.
/// Removes repeated boilerplate across all NSAlert call sites.
@MainActor
enum AlertBuilder {

    /// Shows a non-interactive alert (no confirm/cancel buttons).
    static func show(title: String, message: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.runModal()
    }

    /// Shows a two-button confirm/cancel alert.
    /// Returns `true` if the user clicked `confirmButton`.
    @discardableResult
    static func confirm(
        title: String,
        message: String,
        confirmButton: String,
        cancelButton: String = "Cancel",
        style: NSAlert.Style = .warning
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmButton)
        alert.addButton(withTitle: cancelButton)
        alert.alertStyle = style
        return alert.runModal() == .alertFirstButtonReturn
    }
}
