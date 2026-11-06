import AppKit
import Foundation

/// A focus copied from one harness, ready to paste into another.
struct CopiedFocus: Equatable, Sendable {
    let name: String
    let prompt: String
    let profile: String?
    let sourceHarnessID: String
}

/// App-wide clipboard for harness items copied between harnesses.
///
/// Holds the copied focus in memory so the paste affordance can appear on any
/// harness, and also puts the prompt text on the system pasteboard so it can be
/// pasted elsewhere as plain text.
@MainActor
final class HarnessClipboard: ObservableObject {
    static let shared = HarnessClipboard()

    @Published private(set) var focus: CopiedFocus?

    private let pasteboard: NSPasteboard?

    init(pasteboard: NSPasteboard? = .general) {
        self.pasteboard = pasteboard
    }

    func copy(_ focus: CopiedFocus) {
        self.focus = focus
        pasteboard?.clearContents()
        pasteboard?.setString(focus.prompt, forType: .string)
    }
}

extension FocusEditTarget {
    /// The add-sheet prefill for pasting `focus` into a harness whose profiles
    /// are `availableProfiles`. A profile the target harness lacks is dropped,
    /// so the paste never points at a profile that does not exist there.
    static func pasting(_ focus: CopiedFocus, availableProfiles: [String]) -> FocusEditTarget {
        let profile = focus.profile.flatMap { availableProfiles.contains($0) ? $0 : nil }
        return FocusEditTarget(name: focus.name, prompt: focus.prompt, profile: profile)
    }
}
