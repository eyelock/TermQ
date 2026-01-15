# TermQ Code Style Guide

This document captures code patterns and best practices established during the tech debt cleanup.
Use this as a reference when refactoring or writing new code.

## Swift 6 Concurrency Patterns

### Sendable Conformance

When creating types that will be used in `@MainActor` classes or across concurrency boundaries:

```swift
// ✅ GOOD: Mark Config as Sendable for static property safety
struct Config: Sendable {
    let name: String
    let path: URL
}

// ❌ BAD: Static let with non-Sendable type causes warnings
static let configs = [Config(...)]  // Warning without Sendable
```

### Actor-Isolated Class Patterns

When a `@MainActor` class needs to use dispatch sources or other GCD primitives:

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

// ❌ BAD: Creating dispatch source directly in @MainActor class
// Causes Swift 6 errors about actor isolation
```

### Callback Closure Annotations

Always annotate callbacks with `@Sendable` and `@MainActor` when appropriate:

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

### When to Split

A class is a "god object" candidate when it has:
- Multiple unrelated responsibilities
- More than 400-500 lines
- Mixed concerns (UI state, persistence, business logic)

### Extraction Pattern

1. Identify cohesive groups of methods/properties
2. Create focused manager classes
3. Use callback pattern for coordination
4. Proxy properties for API compatibility

```swift
// ✅ GOOD: Focused managers with clear responsibilities
@MainActor
class BoardViewModel: ObservableObject {
    private let persistence: BoardPersistence  // Save/load
    let tabManager: TabManager                  // Tab state

    // Proxy for backwards compatibility
    var sessionTabs: [UUID] { tabManager.sessionTabs }
}

@MainActor
final class TabManager: ObservableObject {
    // All tab-related state and logic
    @Published private(set) var sessionTabs: [UUID] = []
    private(set) var transientCards: [UUID: TerminalCard] = [:]

    // Callback-based coordination (avoids circular deps)
    private var getBoard: (() -> Board)?
    private var onSave: (() -> Void)?

    func configure(
        board: @escaping () -> Board,
        onSave: @escaping () -> Void
    ) {
        self.getBoard = board
        self.onSave = onSave
    }
}
```

### Init Order with Callbacks

Swift requires all properties initialized before `self` can be captured:

```swift
// ❌ BAD: Can't capture self in init closure
init() {
    self.manager = Manager(
        callback: { [weak self] in self?.handle() }  // Error!
    )
}

// ✅ GOOD: Use configure() pattern
init() {
    self.manager = Manager()
    manager.configure(callback: { [weak self] in self?.handle() })
}
```

## Generic Type Extraction

### When to Use

When multiple implementations share 80%+ identical code:

```swift
// ❌ BAD: Duplicated installer code
class CLIInstaller {
    func install() { /* 100 lines */ }
    func uninstall() { /* 50 lines */ }
}
class MCPServerInstaller {
    func install() { /* 98 lines - nearly identical */ }
    func uninstall() { /* 50 lines - identical */ }
}

// ✅ GOOD: Generic with protocol for differences
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
    func uninstall() { /* Single implementation */ }
}

// Concrete types just define differences
enum CLILocation: String, InstallLocationProtocol, CaseIterable {
    case termqcli

    var relativePath: String { rawValue }
    static var installDir: String { "/usr/local/bin" }
}
```

## Model Separation

### Observable vs Sendable Models

When a model needs both SwiftUI binding AND cross-module sharing:

```swift
// TermQCore: Observable for SwiftUI (not Sendable)
@Observable
public class TerminalCard: Identifiable, Hashable, Codable {
    public var title: String = ""
    public var isFavourite: Bool = false
    // SwiftUI can bind directly to this
}

// TermQShared: Sendable for cross-module (not Observable)
public struct MCPCard: Codable, Sendable {
    public let id: UUID
    public var title: String
    public var isFavourite: Bool
    // Can be passed across actor boundaries
}
```

### Shared Module Pattern

For code shared between multiple targets (app, CLI, MCP server):

```
Sources/
├── TermQShared/          # Sendable types for all targets
│   ├── Card.swift        # MCPCard struct
│   ├── Board.swift       # MCPBoard struct
│   ├── BoardLoader.swift # File I/O logic
│   └── OutputTypes.swift # JSON output formats
├── TermQCore/            # Observable types for app
│   ├── TerminalCard.swift
│   └── Board.swift
└── MCPServerLib/         # Uses TermQShared
```

## Testing Patterns

### MCP Type Extraction

When testing MCP handlers, use helper functions for type extraction:

```swift
// ✅ GOOD: Helper functions for MCP types
private func extractResourceText(from result: ReadResource.Result) -> String {
    guard let firstContent = result.contents.first else { return "" }
    return firstContent.text ?? ""
}

private func extractPromptText(from message: Prompt.Message) -> String {
    if case .text(let text) = message.content {
        return text
    }
    return ""
}

// Use in tests
func testResourceTerminals() async throws {
    let result = try await server.dispatchResourceRead(params)
    let json = extractResourceText(from: result)
    let terminals = try JSONDecoder().decode([TerminalOutput].self, from: Data(json.utf8))
    XCTAssertEqual(terminals.count, 4)
}
```

### Test Data Isolation

Always use temporary directories for test data:

```swift
class MCPIntegrationTests: XCTestCase {
    var tempDirectory: URL!

    override func setUpWithError() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, ...)
        tempDirectory = tempDir
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }
}
```

## Error Handling Guidelines

### Context-Specific Patterns

Different parts of the codebase require different error handling strategies:

#### CLI Commands (termq-cli)

Always throw errors - let ArgumentParser handle user presentation:

```swift
// ✅ GOOD: Throw typed errors
func run() throws {
    guard let board = try? BoardLoader.load(from: path) else {
        throw CLIError.boardNotFound(path: path)
    }
    // ...
}

// ❌ BAD: Silent failure or print
func run() throws {
    if let board = try? BoardLoader.load(from: path) {
        // User never knows why nothing happened
    }
}
```

#### MCP Handlers (MCPServerLib)

Return structured error responses - never crash:

```swift
// ✅ GOOD: Return isError: true with descriptive message
func handleTool(arguments: [String: Any]) async -> CallTool.Result {
    do {
        let result = try await performOperation()
        return CallTool.Result(content: [.text(result)])
    } catch {
        return CallTool.Result(
            content: [.text("Error: \(error.localizedDescription)")],
            isError: true
        )
    }
}

// ❌ BAD: Throw from handler (crashes MCP connection)
func handleTool(arguments: [String: Any]) async throws -> CallTool.Result {
    throw SomeError() // Don't do this
}
```

#### ViewModels (TermQ App)

Log errors and update UI state - keep app responsive:

```swift
// ✅ GOOD: Handle error, update state, log details
func save() {
    do {
        try persistence.save(board)
    } catch {
        print("Save failed: \(error)")  // For debug console
        showError = true  // Update UI state
        lastError = error.localizedDescription
    }
}

// ❌ BAD: Silent failure
func save() {
    try? persistence.save(board)  // User's data might be lost!
}
```

#### File Operations (Utilities)

Use `try?` ONLY for truly optional operations:

```swift
// ✅ GOOD: Directory creation is best-effort (might exist)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

// ✅ GOOD: Cleanup is best-effort
try? FileManager.default.removeItem(at: tempFile)

// ❌ BAD: Silent failure on critical read
let data = try? Data(contentsOf: configFile)  // Config is required!

// ✅ GOOD: Throw for required files
let data = try Data(contentsOf: configFile)
```

### Error Type Definitions

Use typed errors for better diagnostics:

```swift
// ✅ GOOD: Typed errors with associated values
enum CLIError: Error, LocalizedError {
    case boardNotFound(path: String)
    case terminalNotFound(identifier: String)
    case invalidArgument(name: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .boardNotFound(let path):
            return "Board file not found: \(path)"
        case .terminalNotFound(let id):
            return "Terminal not found: \(id)"
        case .invalidArgument(let name, let reason):
            return "Invalid argument '\(name)': \(reason)"
        }
    }
}

// ❌ BAD: Generic string errors
throw NSError(domain: "", code: 0, userInfo: [
    NSLocalizedDescriptionKey: "Something went wrong"
])
```

### Never Silently Ignore These

Some errors should NEVER be silently ignored:

- User data persistence (board.json save/load)
- Network requests that affect user state
- Permission changes (file permissions, admin operations)
- Configuration file parsing

## Memory Management Patterns

### Closure Capture Rules

Different types have different capture semantics:

```swift
// ✅ GOOD: Class with closure callback - use [weak self]
class TerminalSessionManager {
    func setupCallback() {
        themeManager.onThemeChanged = { [weak self] in
            self?.applyTheme()
        }
    }
}

// ✅ GOOD: SwiftUI View (struct) with event monitor - [self] is fine
struct CommandPaletteView: View {
    @State private var selectedIndex = 0

    func setupKeyMonitor() {
        // Struct captures by value, @State is managed externally
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Access @State properties
            selectedIndex -= 1
            return nil
        }
    }
}

// ❌ BAD: Strong self in class causes retain cycle
class ViewModel {
    func badSetup() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.update()  // Creates retain cycle!
        }
    }
}
```

### Event Monitor Cleanup

Event monitors must be removed when views disappear:

```swift
struct MyView: View {
    @State private var monitor: Any?

    var body: some View {
        content
            .onAppear { setupMonitor() }
            .onDisappear { removeMonitor() }  // Critical!
    }

    private func removeMonitor() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
```

### Timer and Dispatch Source Cleanup

Use deinit for class-based cleanup:

```swift
final class FileMonitor {
    private var source: DispatchSourceFileSystemObject?

    deinit {
        source?.cancel()  // Always cancel dispatch sources
        source = nil
    }
}
```

### Callback-Based Coordination

When using callbacks to avoid circular dependencies, ensure they're set up after init:

```swift
// Parent owns child, child has weak callback
class BoardViewModel {
    let tabManager: TabManager

    init() {
        tabManager = TabManager()
        // Configure after all properties initialized
        tabManager.configure(
            board: { [weak self] in self?.board ?? Board() },
            onSave: { [weak self] in self?.save() }
        )
    }
}
```

## Refactoring Checklist

When upgrading code to these patterns:

1. **Swift 6 Sendable**
   - [ ] Check all static properties for Sendable conformance
   - [ ] Extract GCD code to `@unchecked Sendable` helpers
   - [ ] Add `@Sendable @MainActor` to callbacks as needed

2. **God Object Split**
   - [ ] Identify cohesive responsibility groups
   - [ ] Create focused manager classes
   - [ ] Use `configure()` pattern for callback setup
   - [ ] Add proxy properties for API compatibility
   - [ ] Run tests after each extraction

3. **Generic Extraction**
   - [ ] Compare similar implementations for common code
   - [ ] Define protocol for varying parts
   - [ ] Create generic with protocol constraint
   - [ ] Migrate existing types to use generic

4. **Model Separation**
   - [ ] Observable types in TermQCore (app-only)
   - [ ] Sendable structs in TermQShared (multi-target)
   - [ ] Keep JSON decoding compatible

5. **Testing**
   - [ ] Use helpers for MCP type extraction
   - [ ] Isolate test data in temp directories
   - [ ] Check coverage with `make test.coverage`

6. **Error Handling**
   - [ ] CLI: Throw typed errors, let ArgumentParser handle display
   - [ ] MCP: Return `isError: true` with descriptive message
   - [ ] ViewModels: Log error, update UI state
   - [ ] File ops: `try?` only for optional operations
   - [ ] Never silently ignore data persistence errors

7. **Memory Management**
   - [ ] Use `[weak self]` in class closures and callbacks
   - [ ] `[self]` is OK for struct-based SwiftUI views (value capture)
   - [ ] Event monitors must have cleanup in onDisappear
   - [ ] Timers and dispatch sources need cleanup in deinit
   - [ ] Avoid retain cycles with callback-based coordination
