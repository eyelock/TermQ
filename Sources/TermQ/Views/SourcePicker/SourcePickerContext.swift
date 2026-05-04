import SwiftUI

/// Drives a ``SourcePicker``. Each "add a thing" surface (Install Harness,
/// Add Delegate, Add Include) supplies its own context implementing this
/// protocol. The picker shell handles the tab switcher and chrome; the
/// context supplies the per-tab content and the apply action.
///
/// Phase 1 only models the Select phase (Library + Git URL). The optional
/// Configure phase is added when Phase 2 (Add Delegate) lands a context
/// that needs it.
@MainActor
protocol SourcePickerContext: ObservableObject {
    associatedtype LibraryContent: View
    associatedtype GitURLContent: View

    /// Title shown in the picker header.
    var title: String { get }

    /// Content of the Library tab.
    @ViewBuilder var library: LibraryContent { get }

    /// Content of the Git URL tab.
    @ViewBuilder var gitURLView: GitURLContent { get }
}
