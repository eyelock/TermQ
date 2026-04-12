# Memory Management

## Closure Capture Rules

```swift
// ✅ GOOD: Class with closure callback — use [weak self] to avoid retain cycle
class TerminalSessionManager {
    func setupCallback() {
        themeManager.onThemeChanged = { [weak self] in
            self?.applyTheme()
        }
    }
}

// ✅ GOOD: SwiftUI View (struct) — [self] is fine, struct captures by value
struct CommandPaletteView: View {
    @State private var selectedIndex = 0

    func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            selectedIndex -= 1
            return nil
        }
    }
}

// ❌ BAD: Strong self reference in class creates retain cycle
class ViewModel {
    func badSetup() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.update()  // Retain cycle!
        }
    }
}
```

## Event Monitor Cleanup

Event monitors must be removed when views disappear:

```swift
struct MyView: View {
    @State private var monitor: Any?

    var body: some View {
        content
            .onAppear { setupMonitor() }
            .onDisappear { removeMonitor() }  // Critical — not optional
    }

    private func removeMonitor() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
```

## Timer and Dispatch Source Cleanup

Use `deinit` for class-based cleanup:

```swift
final class FileMonitor {
    private var source: DispatchSourceFileSystemObject?

    deinit {
        source?.cancel()  // Always cancel dispatch sources
        source = nil
    }
}
```

## Callback-Based Coordination

When using callbacks to avoid circular dependencies, ensure setup happens after `init`:

```swift
class BoardViewModel {
    let tabManager: TabManager

    init() {
        tabManager = TabManager()
        // Configure after all properties initialised
        tabManager.configure(
            board: { [weak self] in self?.board ?? Board() },
            onSave: { [weak self] in self?.save() }
        )
    }
}
```

The child (`tabManager`) has a weak callback reference back to the parent — no circular strong reference.
