import SwiftUI

/// The editor's "Resume Previous LLM Session" toggle.
///
/// Availability tracks the installed YNH live: the toggle is only enabled
/// for a harness card whose vendor reports that it can resume, so an older
/// YNH leaves it greyed out rather than emitting a flag it cannot honour.
struct CardEditorResumeToggle: View {
    @ObservedObject var viewModel: CardEditorViewModel
    @ObservedObject private var vendorService = VendorService.shared

    var body: some View {
        SharedToggle(
            label: Strings.Editor.autoResumeSession,
            isOn: $viewModel.autoResumeSession,
            isGloballyEnabled: viewModel.canResumeSession(resumableVendorIDs: vendorService.resumableVendorIDs),
            disabledMessage: Strings.Editor.autoResumeSessionUnavailable,
            helpText: Strings.Editor.autoResumeSessionHelp
        )
    }
}
