import AppKit
import SwiftUI

/// Selectable, wrapping text whose web links are clickable and show the
/// pointing hand. SwiftUI's selectable `Text` shows the text cursor over
/// links, so this wraps a read-only `NSTextView`, which handles both.
struct WheelhouseLinkText: NSViewRepresentable {
    let text: String
    var fontSize: CGFloat = 12
    var secondary = false
    /// Lines shown before the text is cut short; nil for all of it.
    var lineLimit: Int?

    func makeNSView(context: Context) -> NSTextView {
        let view = RowMenuTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.isRichText = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .cursor: NSCursor.pointingHand,
        ]
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        let attributed = Self.attributed(text, fontSize: fontSize, secondary: secondary)
        if view.textStorage?.isEqual(to: attributed) != true {
            view.textStorage?.setAttributedString(attributed)
        }
        view.textContainer?.maximumNumberOfLines = lineLimit ?? 0
        view.textContainer?.lineBreakMode = lineLimit == nil ? .byWordWrapping : .byTruncatingTail
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context) -> CGSize? {
        guard let container = view.textContainer, let layout = view.layoutManager else { return nil }
        let width = max(proposal.width ?? 400, 20)
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        return CGSize(width: width, height: ceil(used.height))
    }

    /// Leaves right-clicks to the row around it, so the row's menu shows
    /// over the text too.
    final class RowMenuTextView: NSTextView {
        override func menu(for event: NSEvent) -> NSMenu? {
            superview?.menu(for: event)
        }
    }

    /// The text in the system font, with every link written with a scheme
    /// made clickable; a name like `ynh.session.id` stays text.
    static func attributed(_ text: String, fontSize: CGFloat, secondary: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: secondary ? NSColor.secondaryLabelColor : NSColor.labelColor,
            ])
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return result
        }
        let nsText = text as NSString
        for match in detector.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let url = match.url, nsText.substring(with: match.range).contains("://") else { continue }
            result.addAttribute(.link, value: url, range: match.range)
        }
        return result
    }
}
