import Foundation
import TermQCore

/// Session-resume handling for init commands.
///
/// The card's `initCommand` is persisted and replayed on every open. `--resume`
/// is applied here, at send time, rather than stored in that string — see
/// `ResumeFlagInjector` for why.
extension TerminalSessionManager {

    /// The vendor whose session this launch could continue, or nil when the
    /// launch is not asking to resume or the card is not a harness card.
    ///
    /// An explicit `override` of `false` always means cold. `true` resumes
    /// regardless of the stored preference. `nil` falls back to the card's
    /// `autoResumeSession` (the reopen default).
    func resumeVendorID(for card: TerminalCard, override: Bool?) -> String? {
        guard override ?? card.autoResumeSession else { return nil }
        guard let vendorID = card.tags.first(where: { $0.key == "vendor" })?.value,
            !vendorID.isEmpty
        else {
            // Not a harness-launched card: no vendor session exists to continue.
            return nil
        }
        return vendorID
    }

    /// Reads and clears the card's one-shot resume override, so it applies to
    /// exactly one launch.
    func consumeResumeOverride(for card: TerminalCard) -> Bool? {
        let override = card.resumeOverrideForNextLaunch
        card.resumeOverrideForNextLaunch = nil
        return override
    }

    /// Returns `command` with the resume decision applied.
    ///
    /// - `override == false`: unchanged, this launch starts cold.
    /// - `override == true`: `--resume` is injected when the vendor supports it
    ///   and any prompt is kept.
    /// - `override == nil`: the reopen default. When the card resumes and the
    ///   vendor supports it, `--resume` is injected and the original prompt is
    ///   stripped, since a reopen continues the session rather than replaying
    ///   the prompt into it.
    ///
    /// The capability check is made here at launch rather than stored with the
    /// intent: a user can upgrade or downgrade YNH at any time. A YNH
    /// predating `--resume` forwards the flag to the vendor CLI bare, which
    /// opens Claude's interactive session picker and hangs the pane;
    /// `supportsResume` is false for such a binary.
    ///
    /// Vendor metadata is only refreshed by a launch request or a harness sheet,
    /// never at app start, so cards that want to resume wait for the first
    /// load; every other card takes the fast path with no wait.
    func resolveInitCommand(
        _ command: String,
        for card: TerminalCard,
        override: Bool? = nil,
        vendorService: VendorService = .shared
    ) async -> String {
        guard let vendorID = resumeVendorID(for: card, override: override) else { return command }
        await vendorService.ensureLoaded()
        let supported =
            vendorService.vendors.first { $0.vendorID == vendorID }?.supportsResume ?? false
        guard supported else { return command }

        let injector = ResumeFlagInjector()
        let base = override == nil ? injector.removingPrompt(from: command) : command
        return injector.inject(into: base)
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

        // Consume before suspending so the override applies to this launch only.
        let override = consumeResumeOverride(for: card)

        Task { @MainActor [weak self] in
            guard let self else { return }
            let resolved = await self.resolveInitCommand(command, for: card, override: override)
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
