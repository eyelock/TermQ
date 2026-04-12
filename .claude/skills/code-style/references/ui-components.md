# Reusable UI Components

TermQ provides a set of reusable SwiftUI components. Always use these instead of duplicating the pattern.

## PathInputField

**Location:** `Sources/TermQ/Views/Components/PathInputField.swift`

For directory/file path inputs with validation and file picker.

**Use when:** working directory inputs, file path configuration, any path needing validation.

```swift
PathInputField(
    label: Strings.Editor.fieldDirectory,
    path: $workingDirectory,
    helpText: Strings.Editor.fieldDirectoryHelp,
    validatePath: true
)
```

## SharedToggle

**Location:** `Sources/TermQ/Views/Components/SharedToggle.swift`

For settings with both global and per-terminal control (two-tier permission systems).

**Use when:** features that can be enabled globally and per-terminal, security-related toggles.

```swift
SharedToggle(
    label: Strings.Editor.allowAgentPrompts,
    isOn: $allowAutorun,
    isGloballyEnabled: globalAllowAgentPrompts,
    disabledMessage: Strings.Editor.allowAgentPromptsDisabledGlobally,
    helpText: Strings.Editor.allowAgentPromptsHelp
)
```

## StatusIndicator

**Location:** `Sources/TermQ/Views/Components/StatusIndicator.swift`

For displaying feature/service status with visual indicators.

**Use when:** installation status (MCP, CLI), feature enablement, service availability.

**States:** `.installed`/`.ready` (green), `.active` (green), `.disabled`/`.inactive` (gray), `.error` (red)

```swift
StatusIndicator(
    icon: "server.rack",
    label: Strings.Settings.mcpTitle,
    status: isMCPInstalled ? .installed : .inactive,
    message: isMCPInstalled ? Strings.Settings.cliInstalled : Strings.Settings.notInstalled
)
```

## LargeTextInput

**Location:** `Sources/TermQ/Views/Components/LargeTextInput.swift`

Multi-line text input with fixed height (prevents layout jumping).

**Use when:** prompt inputs, multi-line configuration text, any text area needing stable layout.

**Note:** Uses `TextEditor` with fixed height, not `TextField` with `.vertical` axis — the latter causes layout jumping during typing.

```swift
LargeTextInput(
    label: Strings.Editor.fieldPersistentContext,
    text: $llmPrompt,
    placeholder: Strings.Editor.fieldPersistentContextHelp,
    helpText: Strings.Editor.fieldPersistentContextHelp,
    minLines: 3,
    maxLines: 8
)
```

## KeyValueEditor

**Location:** `Sources/TermQ/Views/Components/KeyValueEditor.swift`

For managing key-value pairs.

**Use when:** environment variable management, tag editing, key-value configuration.

**Configuration types:** `.environmentVariables`, `.tags` (key-only mode support)

```swift
KeyValueEditor(
    items: $environmentVariables,
    config: .environmentVariables,
    onSave: { saveEnvironmentVariables() }
)
```
