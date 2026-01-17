# TermQ Security Audit Report

**Date:** 2026-01-16
**Auditor:** Claude Code (Expert macOS Security Review)
**Version Reviewed:** Based on commit 59a278a (main branch)
**Scope:** Complete codebase security review focusing on Swift security, MCP Server, CLI tools, and exposed services

---

## Executive Summary

TermQ is a Kanban-style terminal manager for macOS consisting of three main components: a native SwiftUI application, a command-line interface (CLI), and an MCP (Model Context Protocol) server for LLM integration. This audit identifies security characteristics, potential vulnerabilities, and provides remediation recommendations.

### Risk Summary

| Category | Risk Level | Status |
|----------|------------|--------|
| MCP Server HTTP Exposure | **Low** | HTTP mode NOT implemented (safe) |
| Shell Command Injection | **Low** | Proper escaping implemented |
| URL Scheme Security | **Medium** | No caller authentication |
| Data Encryption | **Medium** | No encryption at rest |
| App Sandbox | **Expected** | Disabled (required for terminal apps) |
| File Access Control | **Medium** | No locking mechanism |
| OSC Clipboard Access | **Medium** | Programmatic clipboard access possible |

---

## 1. MCP Server Security Analysis

### 1.1 HTTP Transport Status

**Finding:** The HTTP transport is **NOT exposed** and cannot be used.

**Evidence:** `Sources/MCPServer-CLI/main.swift:70-77`
```swift
if http {
    // HTTP mode with bearer token authentication
    if verbose {
        fputs("Starting HTTP server on port \(port)...\n", stderr)
    }
    // HTTP transport implementation pending
    fputs("HTTP transport not yet implemented. Use stdio mode.\n", stderr)
    throw ExitCode.failure  // ← Execution stops here
}
```

**Assessment:** The MCP server currently only operates in **stdio mode**, which is designed for local process communication (e.g., Claude Code). The HTTP mode with bearer token authentication is defined in the CLI arguments but not implemented. This is **safe by design** - the server cannot be exposed over the network.

**Recommendation:**
- Document clearly that HTTP mode is not functional
- If HTTP mode is implemented in the future:
  - Implement proper bearer token authentication
  - Use TLS/HTTPS only
  - Bind to localhost only by default
  - Add rate limiting
  - Implement proper CORS headers

### 1.2 MCP Input Validation

**Finding:** Input validation is implemented but has some gaps.

**Implemented Validations** (`Sources/MCPServerLib/InputValidator.swift`):
- UUID format validation (lines 75-85)
- Non-empty string validation (lines 50-60)
- Path tilde expansion (line 103)
- Directory existence checking (optional, lines 111-120)

**Gaps Identified:**
1. **No string length limits** - LLM prompts and descriptions can be arbitrarily large
2. **No path traversal prevention** - Paths with `../` are not blocked
3. **No content sanitization** - Tag values, badges, descriptions accept any content
4. **No validation on llmPrompt/llmNextAction content** - Could contain sensitive data

**Remediation:**
```swift
// Add maximum length validation
static func validateStringLength(_ value: String, maxLength: Int = 10000) throws -> String {
    guard value.count <= maxLength else {
        throw ValidationError.stringTooLong(parameter: name, maxLength: maxLength)
    }
    return value
}

// Add path traversal prevention
static func validatePath(_ value: String) throws -> String {
    let normalized = (value as NSString).standardizingPath
    // Reject if path escapes expected boundaries
    guard !normalized.contains("..") else {
        throw ValidationError.pathTraversal(parameter: name)
    }
    return normalized
}
```

---

## 2. Shell Command Execution Security

### 2.1 Shell Argument Escaping

**Finding:** Shell escaping is **properly implemented**.

**Evidence:** `Sources/TermQ/ViewModels/TerminalSessionManager.swift:681-683`
```swift
private func escapeShellArg(_ arg: String) -> String {
    return "'" + arg.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}
```

**Assessment:** This is the correct technique for shell argument escaping:
- Wraps arguments in single quotes (prevents shell interpretation)
- Handles embedded single quotes by breaking out, adding escaped quote, continuing
- Applied consistently to all user-controlled values: paths, session names, shell paths, tmux paths

**Usage Examples (correctly escaped):**
```swift
// Line 232 - Direct process startup
let startCommand = "cd \(escapeShellArg(card.workingDirectory)) && exec \(escapeShellArg(card.shellPath)) -l"

// Line 274-287 - Tmux script
let script = """
    if ! \(escapeShellArg(tmuxPath)) has-session -t \(escapeShellArg(sessionName)) 2>/dev/null; then
        \(escapeShellArg(tmuxPath)) new-session -d -s \(escapeShellArg(sessionName)) -c \(escapeShellArg(card.workingDirectory)) ...
```

### 2.2 Environment Variable Sanitization

**Finding:** Environment variable names are **properly sanitized**.

**Evidence:** `Sources/TermQ/ViewModels/TerminalSessionManager.swift:689-706`
```swift
private func sanitizeEnvVarName(_ name: String) -> String {
    var result = name.uppercased()
    // Replace any character that isn't A-Z, 0-9, or underscore with underscore
    result = result.map { char -> Character in
        if char.isLetter || char.isNumber || char == "_" {
            return char
        }
        return "_"
    }.reduce("") { String($0) + String($1) }
    // Remove leading digits/underscores
    while let first = result.first, first.isNumber || first == "_" {
        result.removeFirst()
    }
    return result
}
```

**Assessment:** Tag keys are properly sanitized before being used as environment variable names (`TERMQ_TERMINAL_TAG_<KEY>`).

---

## 3. URL Scheme Security

### 3.1 URL Scheme Handler

**Finding:** Any process can invoke `termq://` URLs without authentication.

**Evidence:** `Sources/TermQ/TermQApp.swift:377-384`
```swift
NSAppleEventManager.shared().setEventHandler(
    URLEventHandler.shared,
    andSelector: #selector(URLEventHandler.handleURL(_:replyEvent:)),
    forEventClass: AEEventClass(kInternetEventClass),
    andEventID: AEEventID(kAEGetURL)
)
```

**Supported Operations:**
- `termq://open` - Create new terminal with parameters
- `termq://update` - Modify terminal properties (name, description, llmPrompt, llmNextAction, tags, badge)
- `termq://move` - Move terminal between columns
- `termq://focus` - Focus/select a terminal

**Risk Assessment:**
- **Caller Identification:** None - any process on the system can invoke these URLs
- **Authorization:** None - operations execute without user confirmation
- **Data Modification:** External processes can modify terminal metadata including LLM prompts

**Attack Scenarios:**
1. **LLM Prompt Injection:** Malicious process sets `llmNextAction` to execute commands when user opens terminal with LLM
2. **Information Disclosure:** External process could read board.json to discover terminal names, paths, and contexts
3. **State Manipulation:** External process could move terminals, change badges, modify descriptions

**Remediation Options:**
1. **User Confirmation for Sensitive Operations:**
   ```swift
   private func handleUpdate(queryItems: [URLQueryItem]) {
       // Show confirmation for LLM field modifications
       if queryItems.contains(where: { $0.name == "llmPrompt" || $0.name == "llmNextAction" }) {
           guard showConfirmationDialog("Allow external application to modify LLM context?") else {
               return
           }
       }
       // ... proceed with update
   }
   ```

2. **Origin Verification (macOS 10.15+):**
   ```swift
   // Use NSWorkspace to identify calling application
   func handleURL(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
       if let sourceBundle = event.attributeDescriptor(forKeyword: keyAddressAttr)?.bundleIdentifier {
           // Log or verify source bundle
       }
   }
   ```

3. **Rate Limiting:**
   - Add rate limiting to prevent rapid-fire URL invocations
   - Implement cooldown between operations from same source

---

## 4. Data Storage Security

### 4.1 Data Location and Encryption

**Finding:** Data is stored **unencrypted** in plaintext JSON.

**Location:** `~/Library/Application Support/TermQ/board.json`

**Sensitive Data Exposed:**
- Full filesystem paths to working directories
- LLM prompts (may contain project context, credentials mentioned in context)
- LLM next actions (may contain command sequences)
- Terminal descriptions and notes
- Tag values (could contain sensitive metadata)

**Risk:** Any process with file read permissions can access this data. Subject only to full-disk encryption if enabled at OS level.

**Remediation Options:**

1. **Keychain Integration for Sensitive Fields:**
   ```swift
   func saveSecurefield(_ value: String, for key: String) throws {
       let data = value.data(using: .utf8)!
       let query: [String: Any] = [
           kSecClass as String: kSecClassGenericPassword,
           kSecAttrAccount as String: key,
           kSecValueData as String: data
       ]
       SecItemAdd(query as CFDictionary, nil)
   }
   ```

2. **Data Classification:**
   - Mark llmPrompt and llmNextAction as "sensitive"
   - Store sensitive fields encrypted or in Keychain
   - Keep non-sensitive operational data in JSON

3. **File Permissions Hardening:**
   ```swift
   // Set restrictive permissions on board.json
   try FileManager.default.setAttributes(
       [.posixPermissions: 0o600],  // Owner read/write only
       ofItemAtPath: boardURL.path
   )
   ```

### 4.2 File Locking

**Finding:** No file locking mechanism for concurrent access.

**Evidence:** `Sources/TermQShared/BoardLoader.swift` uses `Data(contentsOf:)` and `write(to:options:.atomic)` without locking.

**Risk:** Race conditions when multiple processes (CLI, MCP, GUI) write simultaneously. Last write wins, potentially losing data.

**Remediation:**
```swift
// Use file coordination
let coordinator = NSFileCoordinator()
var error: NSError?
coordinator.coordinate(writingItemAt: boardURL, options: [], error: &error) { url in
    try? jsonData.write(to: url, options: .atomic)
}
```

---

## 5. Entitlements and Sandbox Analysis

### 5.1 Current Entitlements

**File:** `TermQ.entitlements`

```xml
<!-- Sandbox disabled -->
<key>com.apple.security.app-sandbox</key>
<false/>

<!-- Full filesystem access -->
<key>com.apple.security.files.all</key>
<true/>

<!-- Unsigned executable memory -->
<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
<true/>

<!-- Library validation disabled -->
<key>com.apple.security.cs.disable-library-validation</key>
<true/>

<!-- JIT compilation -->
<key>com.apple.security.cs.allow-jit</key>
<true/>

<!-- Network client and server -->
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>

<!-- Serial device access -->
<key>com.apple.security.device.serial</key>
<true/>
```

**Assessment:** These entitlements are **expected and necessary** for a terminal emulator application:
- Terminal apps need to spawn shell processes
- Shell processes need filesystem access
- Tools within terminals (git, npm, etc.) need network access
- Some terminal workflows involve serial devices

**However, this creates an elevated attack surface:**
- The app runs with full user privileges
- Any vulnerability in the app could be exploited for user-level access
- No macOS sandbox protections are active

**Recommendation:**
- Document the security implications clearly
- Consider hardened runtime options where possible
- Ensure code signing is properly configured for notarization

---

## 6. Terminal Emulation Security

### 6.1 OSC Escape Sequence Handlers

**Finding:** OSC handlers allow programmatic clipboard and notification access.

**Evidence:** `Sources/TermQ/Views/TerminalHostView.swift:104-126`

**Handlers Implemented:**
1. **OSC 52 - Clipboard:** Allows terminal programs to write to system clipboard
   ```swift
   terminal.registerOscHandler(code: 52) { [weak self] data in
       self?.handleClipboardOsc(data)  // Decodes base64 and writes to clipboard
   }
   ```

2. **OSC 777 - Notifications:** Allows terminal programs to show desktop notifications
3. **OSC 9 - Simple Notifications:** Windows Terminal format notifications

**Risk Assessment:**
- **Clipboard:** Malicious terminal content could silently copy data to clipboard
- **Notifications:** Phishing potential via fake notification content

**Remediation:**
1. **Add user preference to disable OSC 52:**
   ```swift
   if UserDefaults.standard.bool(forKey: "allowOscClipboard") {
       terminal.registerOscHandler(code: 52) { ... }
   }
   ```

2. **Rate limit clipboard operations**
3. **Show visual indicator when clipboard is written via OSC 52**

### 6.2 Safe Paste Protection

**Finding:** Good security feature implemented.

**Evidence:** `Sources/TermQ/Views/TerminalHostView.swift:353-385`

The `SafePasteAnalyzer` warns users about:
- Commands with `sudo`
- Multi-line pastes (potential command injection)
- Dangerous commands (rm -rf, etc.)

**Assessment:** This is a **positive security feature** that helps prevent accidental command execution.

---

## 7. Dependency Security

### 7.1 Critical Dependencies

| Package | Version | Risk Level | Notes |
|---------|---------|------------|-------|
| SwiftTerm | 5e9b2e31 (pinned commit) | Medium | Terminal emulation, ANSI parsing |
| swift-subprocess | main branch (unpinned) | High | Process execution |
| swift-sdk (MCP) | 0.10.2 | Medium | Protocol implementation |
| swift-argument-parser | 1.7.0 | Low | CLI parsing |
| swift-log | 1.8.0 | Low | Logging |

**Recommendations:**
1. **Pin swift-subprocess to specific version:**
   ```swift
   .package(url: "...", exact: "x.y.z")  // Instead of branch: "main"
   ```
2. **Regularly audit SwiftTerm for security updates** (terminal emulation is security-critical)
3. **Monitor swift-sdk for protocol security advisories**

---

## 8. TmuxManager Security

### 8.1 Tmux Path Detection

**Finding:** Tmux is located via predetermined paths and PATH lookup.

**Evidence:** `Sources/TermQ/Services/TmuxManager.swift:38-61`

**Paths Checked:**
1. `/opt/homebrew/bin/tmux` (Apple Silicon Homebrew)
2. `/usr/local/bin/tmux` (Intel Homebrew)
3. `/usr/bin/tmux` (System)
4. `/opt/local/bin/tmux` (MacPorts)
5. `which tmux` fallback

**Assessment:** The path verification uses `FileManager.default.isExecutableFile(atPath:)` which is appropriate.

### 8.2 Metadata Storage

**Finding:** Terminal metadata is stored in tmux session environment variables.

**Evidence:** Lines 221-227
```swift
func setSessionMetadata(name: String, key: String, value: String) async throws {
    _ = try await runCommand(path, args: ["set-environment", "-t", name, "TERMQ_\(key)", value])
}
```

**Risk:** LLM prompts and actions are stored unencrypted in tmux environment. Any process can read via `tmux show-environment`.

---

## 9. Recommendations Summary

### Critical (Address Immediately)

| # | Issue | Remediation |
|---|-------|-------------|
| 1 | No file locking for board.json | Implement NSFileCoordinator |
| 2 | Unpinned swift-subprocess dependency | Pin to specific version |

### High Priority (Address Soon)

| # | Issue | Remediation |
|---|-------|-------------|
| 3 | No string length limits in input validation | Add maxLength validation |
| 4 | URL scheme accepts modifications without confirmation | Add user confirmation for sensitive fields |
| 5 | OSC 52 clipboard access unconditional | Add user preference to disable |

### Medium Priority (Plan for Future)

| # | Issue | Remediation |
|---|-------|-------------|
| 6 | Unencrypted sensitive data storage | Consider Keychain for llmPrompt/llmNextAction |
| 7 | No path traversal prevention | Validate and normalize paths |
| 8 | No audit logging | Add logging for security-sensitive operations |

### Low Priority (Consider)

| # | Issue | Remediation |
|---|-------|-------------|
| 9 | Detailed error messages may leak paths | Sanitize error messages for external display |
| 10 | No rate limiting on URL scheme | Implement basic rate limiting |

---

## 10. Conclusion

TermQ demonstrates **good security practices** in several areas:
- Proper shell argument escaping
- Safe paste protection
- MCP HTTP mode not exposed
- Environment variable sanitization
- Atomic file writes

The primary security considerations stem from the **inherent requirements of terminal applications**:
- No sandbox (necessary for shell process spawning)
- Full filesystem access (necessary for terminal workflows)
- URL scheme accessibility (convenience feature with security trade-offs)

The application's security posture is **appropriate for its intended use case** as a local development tool. The documented risks are acceptable for single-user desktop operation but would require significant hardening for any multi-user or networked deployment scenario.

---

## Appendix A: Files Reviewed

- `Sources/MCPServer-CLI/main.swift`
- `Sources/MCPServerLib/Server.swift`
- `Sources/MCPServerLib/ToolHandlers.swift`
- `Sources/MCPServerLib/InputValidator.swift`
- `Sources/TermQ/TermQApp.swift`
- `Sources/TermQ/ViewModels/TerminalSessionManager.swift`
- `Sources/TermQ/Views/TerminalHostView.swift`
- `Sources/TermQ/Services/TmuxManager.swift`
- `Sources/TermQShared/BoardLoader.swift`
- `Sources/termq-cli/CLI.swift`
- `TermQ.entitlements`
- `SECURITY.md`

## Appendix B: Security Testing Commands

```bash
# Check for hardcoded secrets
grep -r "password\|secret\|key\|token" Sources/ --include="*.swift"

# Verify shell escaping is used consistently
grep -r "escapeShellArg" Sources/

# Find all URL scheme handlers
grep -r "termq://" Sources/

# Check file permissions on data directory
ls -la ~/Library/Application\ Support/TermQ/

# Verify tmux session environment variables
tmux show-environment -t termq-<session-id>
```
