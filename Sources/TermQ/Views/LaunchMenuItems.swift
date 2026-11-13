import SwiftUI

/// The launch group at the top of every menu that can start a harness, so
/// each one reads the same:
///
/// - **Quick Launch <harness>**: the harness's defaults, no dialog.
/// - **Launch <harness>…**: the launch sheet, to pick a focus, a prompt and
///   the rest.
/// - **Launch with Focus ▸**: one of the harness's focuses, no dialog.
///
/// Items whose action is nil are left out.
struct LaunchMenuItems: View {
    struct Focus: Identifiable {
        let name: String
        let action: () -> Void
        var id: String { name }
    }

    /// The harness (or seat) the items launch; nil when the sheet picks it.
    let name: String?
    var quickLaunch: (() -> Void)?
    var openSheet: (() -> Void)?
    var focuses: [Focus] = []
    /// The focus submenu's title: "Launch with Focus" unless the target is
    /// already running, where a focus is asked of its session instead.
    var focusTitle: String = Strings.Launch.withFocus

    var body: some View {
        if let quickLaunch, let name {
            Button(action: quickLaunch) {
                Label(Strings.Launch.quick(name), systemImage: LaunchMenuIcon.quickLaunch)
            }
        }
        if let openSheet {
            Button(action: openSheet) {
                Label(name.map(Strings.Launch.sheet) ?? Strings.Launch.sheetAny, systemImage: LaunchMenuIcon.sheet)
            }
        }
        if !focuses.isEmpty {
            Menu {
                ForEach(focuses) { focus in
                    Button(action: focus.action) {
                        Label(focus.name, systemImage: WheelhouseMenuIcon.focus(named: focus.name))
                    }
                }
            } label: {
                Label(focusTitle, systemImage: LaunchMenuIcon.focus)
            }
        }
    }
}

/// Symbols for the launch and terminal items, the same in every menu.
enum LaunchMenuIcon {
    static let quickLaunch = "play.fill"
    static let sheet = "slider.horizontal.3"
    static let focus = "scope"
    /// Quick Terminal: a shell, no dialog.
    static let quickTerminal = "terminal"
    /// New Terminal…: the terminal editor.
    static let newTerminal = "plus.rectangle"
}
