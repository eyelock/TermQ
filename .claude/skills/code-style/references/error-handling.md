# Error Handling

Different parts of the codebase require different error handling strategies. Match the strategy to the context.

## CLI Commands (`termq-cli`)

Always throw — let ArgumentParser handle user presentation:

```swift
// ✅ GOOD: Throw typed errors
func run() throws {
    guard let board = try? BoardLoader.load(from: path) else {
        throw CLIError.boardNotFound(path: path)
    }
}

// ❌ BAD: Silent failure — user never knows why nothing happened
func run() throws {
    if let board = try? BoardLoader.load(from: path) {
        // ...
    }
}
```

## MCP Handlers (`MCPServerLib`)

Return structured error responses — never throw, never crash:

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

// ❌ BAD: Throwing from a handler crashes the MCP connection
func handleTool(arguments: [String: Any]) async throws -> CallTool.Result {
    throw SomeError()
}
```

## ViewModels (`TermQ` app)

Log the error and update UI state — keep the app responsive:

```swift
// ✅ GOOD: Handle error, update state, log details
func save() {
    do {
        try persistence.save(board)
    } catch {
        print("Save failed: \(error)")
        showError = true
        lastError = error.localizedDescription
    }
}

// ❌ BAD: Silent failure — user's data might be lost
func save() {
    try? persistence.save(board)
}
```

## File Operations

Use `try?` **only** for truly optional operations:

```swift
// ✅ GOOD: Directory creation is best-effort (might already exist)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

// ✅ GOOD: Cleanup is best-effort
try? FileManager.default.removeItem(at: tempFile)

// ❌ BAD: Silent failure on a required read
let data = try? Data(contentsOf: configFile)  // Config is required!

// ✅ GOOD: Throw for required files
let data = try Data(contentsOf: configFile)
```

## Typed Error Definitions

```swift
// ✅ GOOD: Typed errors with associated values
enum CLIError: Error, LocalizedError {
    case boardNotFound(path: String)
    case terminalNotFound(identifier: String)
    case invalidArgument(name: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .boardNotFound(let path): return "Board file not found: \(path)"
        case .terminalNotFound(let id): return "Terminal not found: \(id)"
        case .invalidArgument(let name, let reason): return "Invalid argument '\(name)': \(reason)"
        }
    }
}

// ❌ BAD: Generic string errors
throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Something went wrong"])
```

## Never Silently Ignore These

Some errors must never be silently dropped:

- User data persistence (board.json save/load)
- Network requests that affect user state
- Permission changes
- Configuration file parsing
