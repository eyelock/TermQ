# Testing Patterns

## MCP Type Extraction

MCP result types require helper functions for clean extraction in tests:

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

## Test Data Isolation

Always use temporary directories — never write test data to fixed paths:

```swift
class MCPIntegrationTests: XCTestCase {
    var tempDirectory: URL!

    override func setUpWithError() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        tempDirectory = tempDir
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }
}
```

## Test Coverage

Run coverage reports with:

```bash
make test.coverage
```

Critical paths that must have test coverage:
- Board persistence (save/load round-trips)
- MCP handler responses (success and error cases)
- CLI command execution
- Localization string key consistency
