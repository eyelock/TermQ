# Swift Concurrency Patterns

## Sendable Conformance

Mark structs and enums as `Sendable` when used in `@MainActor` classes or across concurrency boundaries:

```swift
// ✅ GOOD: Mark Config as Sendable for static property safety
struct Config: Sendable {
    let name: String
    let path: URL
}

// ❌ BAD: Static let with non-Sendable type causes warnings
static let configs = [Config(...)]  // Warning without Sendable
```

## Actor-Isolated Class Patterns

When a `@MainActor` class needs GCD primitives, extract them into `@unchecked Sendable` helpers:

```swift
// ✅ GOOD: Extract non-actor helper for dispatch source
final class FileMonitor: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private let onChange: @Sendable () -> Void

    init(path: String, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        // Setup dispatch source here
    }
}

// Use from @MainActor class
@MainActor
class BoardPersistence {
    private var fileMonitor: FileMonitor?

    func startMonitoring() {
        fileMonitor = FileMonitor(path: path) { [weak self] in
            Task { @MainActor in
                self?.handleChange()
            }
        }
    }
}

// ❌ BAD: Creating dispatch source directly in @MainActor class causes Swift 6 errors
```

## Callback Closure Annotations

```swift
// ✅ GOOD: Explicit annotations for thread safety
func getOrCreateSession(
    onExit: @escaping @Sendable @MainActor () -> Void,
    onBell: @escaping () -> Void
) -> View

// For delegate callbacks that hop to main actor:
func processTerminated(source: TerminalView, exitCode: Int32?) {
    let onExit = self.onExit  // Capture before Task
    Task { @MainActor in
        onExit()
    }
}
```

## God Object Decomposition

A class needs splitting when it has: multiple unrelated responsibilities, 400+ lines, or mixed concerns (UI state, persistence, business logic).

**Extraction pattern:**

```swift
// ✅ GOOD: Focused managers with clear responsibilities
@MainActor
class BoardViewModel: ObservableObject {
    private let persistence: BoardPersistence
    let tabManager: TabManager

    // Proxy for backwards compatibility
    var sessionTabs: [UUID] { tabManager.sessionTabs }
}

@MainActor
final class TabManager: ObservableObject {
    @Published private(set) var sessionTabs: [UUID] = []
    private(set) var transientCards: [UUID: TerminalCard] = [:]

    private var getBoard: (() -> Board)?
    private var onSave: (() -> Void)?

    func configure(board: @escaping () -> Board, onSave: @escaping () -> Void) {
        self.getBoard = board
        self.onSave = onSave
    }
}
```

## Init Order with Callbacks

Swift requires all properties to be initialised before `self` can be captured. Use `configure()`:

```swift
// ❌ BAD: Can't capture self in init closure
init() {
    self.manager = Manager(callback: { [weak self] in self?.handle() })  // Error!
}

// ✅ GOOD: Use configure() pattern
init() {
    self.manager = Manager()
    manager.configure(callback: { [weak self] in self?.handle() })
}
```

## Generic Type Extraction

When multiple implementations share 80%+ identical code:

```swift
// ✅ GOOD: Generic with protocol for the varying parts
protocol InstallLocationProtocol: Sendable {
    var relativePath: String { get }
    var description: String { get }
    static var installDir: String { get }
}

class ComponentInstaller<Location: InstallLocationProtocol> {
    struct Config: Sendable {
        let productName: String
        let locations: [Location]
    }

    func install() { /* Single implementation */ }
}

enum CLILocation: String, InstallLocationProtocol, CaseIterable {
    case termqcli
    var relativePath: String { rawValue }
    static var installDir: String { "/usr/local/bin" }
}
```

## Model Separation

```swift
// TermQCore: Observable for SwiftUI (not Sendable)
@Observable
public class TerminalCard: Identifiable, Hashable, Codable {
    public var title: String = ""
    public var isFavourite: Bool = false
}

// TermQShared: Sendable for cross-module (not Observable)
public struct MCPCard: Codable, Sendable {
    public let id: UUID
    public var title: String
    public var isFavourite: Bool
}
```
