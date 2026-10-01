import Foundation
import TermQCore

/// Session-resume handling for init commands.
///
/// The card's `initCommand` is persisted and replayed on every open. `--resume`
/// is applied here, at send time, rather than stored in that string — see
/// `ResumeFlagInjector` for why.
extension TerminalSessionManager {

    /// Whether this card's launch should carry `--resume`.
    ///
    /// Requires both the user's intent (`autoResumeSession`) and live vendor
    /// support. The capability check is deliberately made here at launch rather
    /// than stored with the intent: a user can upgrade or downgrade YNH at any
    /// time, and the stored preference should survive that without silently
    /// producing a command the installed binary cannot honour.
    ///
    /// The failure mode this guards is specific. A YNH predating `--resume`
    /// forwards unrecognised flags straight to the vendor CLI, so the flag
    /// would arrive at Claude bare — opening its interactive session picker and
    /// hanging the pane on a keypress that never comes. `supportsResume` is
    /// false for such a binary because the field is simply absent from its
    /// `ynh vendors` output.
    func shouldResumeSession(for card: TerminalCard) -> Bool {
        guard let vendorID = resumeVendorID(for: card) else { return false }
        return VendorService.shared.vendors
            .first { $0.vendorID == vendorID }?
            .supportsResume ?? false
    }

    /// The vendor whose session the card wants to continue, or nil when the
    /// card is not asking to resume or is not a harness card at all.
    func resumeVendorID(for card: TerminalCard) -> String? {
        guard card.autoResumeSession else { return nil }
        guard let vendorID = card.tags.first(where: { $0.key == "vendor" })?.value,
            !vendorID.isEmpty
        else {
            // Not a harness-launched card: no vendor session exists to continue.
            return nil
        }
        return vendorID
    }

    /// Returns `command` with `--resume` applied when the card asks for it and
    /// the installed YNH can honour it.
    ///
    /// Vendor metadata is only refreshed by a launch request or a harness sheet,
    /// never at app start, so a card reopened straight after launch would see an
    /// empty vendor list and silently start cold. Cards that want to resume wait
    /// for the first load; every other card is untouched by this path.
    func resolveInitCommand(_ command: String, for card: TerminalCard) async -> String {
        guard resumeVendorID(for: card) != nil else { return command }
        await VendorService.shared.ensureLoaded()
        guard shouldResumeSession(for: card) else { return command }
        return ResumeFlagInjector().inject(into: command)
    }

    /// Sends the init command once the resume decision is made.
    ///
    /// The send delay for direct and tmux-attach backends is measured from now,
    /// not from when the vendor list arrives, so a card that does not resume
    /// keeps exactly the timing it had before.
    func dispatchInitCommand(
        _ command: String,
        to terminal: TermQTerminalView,
        for card: TerminalCard,
        backend: TerminalBackend
    ) {
        let delay: Double = backend == .tmuxAttach ? 0.8 : 0.5
        let deadline: DispatchTime = .now() + delay

        Task { @MainActor [weak self] in
            guard let self else { return }
            let resolved = await self.resolveInitCommand(command, for: card)
            // The pane may have been closed while the vendor list loaded.
            guard self.sessionExists(for: card.id) else { return }

            if backend == .tmuxControl {
                self.sendInitCommandViaControlMode(cardId: card.id, command: resolved)
            } else {
                // Direct or tmux-attach: send text directly to the terminal.
                DispatchQueue.main.asyncAfter(deadline: deadline) {
                    terminal.send(txt: resolved + "\n")
                }
            }
        }
    }
}
