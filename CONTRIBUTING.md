# Contributing to TermQ

Thank you for your interest in contributing to TermQ! This guide will help you get started.

## Table of Contents

- [Quick Start](#quick-start)
- [Requirements](#requirements)
- [Development Workflow](#development-workflow)
- [Project Structure](#project-structure)
- [Building](#building)
- [Testing](#testing)
- [Linting & Formatting](#linting--formatting)
- [Debugging](#debugging)
- [Releasing](#releasing)
- [CI/CD](#cicd)
- [Makefile Reference](#makefile-reference)
- [Localization](#localization)
- [Dependencies](#dependencies)

## Quick Start

```bash
# Clone and build
git clone https://github.com/eyelock/termq.git
cd termq
make sign
open TermQ.app
```

## Requirements

| Requirement | For | Notes |
|-------------|-----|-------|
| macOS 14.0+ | Building & running | Required |
| Xcode Command Line Tools | Building | `xcode-select --install` |
| Full Xcode.app | Unit tests & linting | Download from App Store |
| SwiftLint | Linting | `brew install swiftlint` (requires Xcode) |
| swift-format | Formatting | `brew install swift-format` |

> **Important**: Unit tests and SwiftLint require the full Xcode.app installation, not just Command Line Tools. If you only have Command Line Tools, you can still build and run the app - tests will run in CI.

## Development Workflow

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes
4. Run checks: `make check`
5. Commit: `git commit -m 'Add amazing feature'`
6. Push: `git push origin feature/amazing-feature`
7. Open a Pull Request

## Project Structure

```
termq/
├── Package.swift              # Swift Package Manager manifest
├── VERSION                    # Current version (semver)
├── Makefile                   # Build, test, lint, release commands
├── TermQ.app/                 # macOS app bundle
│   └── Contents/
│       ├── Info.plist         # App metadata & URL scheme
│       └── MacOS/             # Binary location
├── TermQ.entitlements         # Code signing entitlements
├── Sources/
│   ├── TermQCore/             # Core library (testable models)
│   │   ├── Board.swift
│   │   ├── Column.swift
│   │   ├── Tag.swift
│   │   └── TerminalCard.swift
│   ├── TermQ/                 # Main app
│   │   ├── TermQApp.swift     # App entry point & URL handling
│   │   ├── ViewModels/
│   │   │   ├── BoardViewModel.swift
│   │   │   └── TerminalSessionManager.swift
│   │   └── Views/
│   │       ├── ContentView.swift
│   │       ├── KanbanBoardView.swift
│   │       ├── ColumnView.swift
│   │       ├── TerminalCardView.swift
│   │       ├── ExpandedTerminalView.swift
│   │       ├── TerminalHostView.swift
│   │       ├── CardEditorView.swift
│   │       └── ColumnEditorView.swift
│   └── termq-cli/             # CLI tool
│       └── main.swift
├── Tests/
│   └── TermQTests/            # Unit tests
└── .github/
    └── workflows/
        ├── ci.yml             # CI workflow
        └── release.yml        # Release workflow
```

## Building

```bash
make build          # Debug build
make build-release  # Release build
make sign           # Build and sign debug app bundle
make release-app    # Build and sign release app bundle
make install        # Install CLI to /usr/local/bin
```

Run the app:

```bash
open TermQ.app
# Or directly from build output
.build/debug/TermQ
```

## Testing

Tests require full Xcode (not just Command Line Tools):

```bash
make test
# Or
swift test
```

> **Note:** If you only have Command Line Tools installed, tests will fail locally but will run in CI (GitHub Actions has full Xcode).

## Linting & Formatting

```bash
# Install tools (first time only)
make install-swiftlint
make install-swift-format

# Lint
make lint           # Check for issues
make lint-fix       # Auto-fix issues

# Format
make format         # Format all code
make format-check   # Check formatting (CI mode)

# Run all checks
make check
```

## Debugging

### Console Output

Run the app from terminal to see logs:

```bash
.build/debug/TermQ
```

### Xcode Debugging

Generate an Xcode project for full debugging support:

```bash
swift package generate-xcodeproj
open TermQ.xcodeproj
```

Then use Xcode's debugger, breakpoints, and Instruments.

### Key Files for Debugging

| Issue | File to Check |
|-------|---------------|
| Terminal sessions | `TerminalSessionManager.swift` |
| Board persistence | `BoardViewModel.swift` |
| URL scheme handling | `TermQApp.swift` |
| Drag & drop | `ColumnView.swift` |

### URL Scheme Testing

Test CLI integration:

```bash
open "termq://open?name=Test&path=/tmp"
```

## Releasing

The project uses [semantic versioning](https://semver.org/). The current version is stored in the `VERSION` file.

### Pre-Release Checklist

Before releasing, ensure code hygiene:

```bash
# 1. Run all checks
make check

# 2. Validate localization strings
./scripts/localization/validate-strings.sh

# 3. Run tests
make test
```

> **Important**: The localization validation ensures all 40 language files have matching keys. Any missing translations will cause the release to fail in CI.

### Interactive Release

```bash
make release
```

This will:
1. Show current version and ask for release type (major/minor/patch)
2. Check for uncommitted changes
3. Update the VERSION file
4. Commit the version bump
5. Create a git tag (e.g., `v0.1.0`)
6. Ask to push (which triggers the release workflow)

### Direct Release

```bash
make release-patch  # Bug fixes: 0.0.1 → 0.0.2
make release-minor  # New features: 0.0.1 → 0.1.0
make release-major  # Breaking changes: 0.0.1 → 1.0.0
```

### Manual Release

```bash
echo "1.0.0" > VERSION
git add VERSION
git commit -m "Bump version to 1.0.0"
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin main
git push origin v1.0.0
```

## CI/CD

### Pull Requests & Pushes

The CI workflow (`.github/workflows/ci.yml`) runs on every push and PR:

- Build verification
- Unit tests
- SwiftLint
- Format check
- Uploads build artifacts

### Releases

The release workflow (`.github/workflows/release.yml`) triggers on version tags (`v*`):

- Builds release binaries
- Creates signed app bundle
- Generates checksums
- Publishes GitHub Release with:
  - `TermQ-{version}.dmg` - Installer disk image
  - `TermQ-{version}.zip` - App bundle (CLI tool bundled inside)
  - `checksums.txt` - SHA-256 hashes

## Makefile Reference

Run `make help` for all available targets:

| Target | Description |
|--------|-------------|
| `build` | Build debug version |
| `build-release` | Build release version |
| `clean` | Clean build artifacts |
| `test` | Run tests (requires Xcode) |
| `lint` | Run SwiftLint |
| `lint-fix` | Run SwiftLint with auto-fix |
| `format` | Format code with swift-format |
| `format-check` | Check formatting (CI mode) |
| `check` | Run all checks |
| `app` | Build debug app bundle |
| `sign` | Build and sign debug app |
| `release-app` | Build and sign release app |
| `install` | Install CLI to /usr/local/bin |
| `uninstall` | Remove CLI |
| `dmg` | Create distributable DMG |
| `zip` | Create distributable zip |
| `version` | Show current version |
| `release` | Interactive release |
| `release-major` | Release major version |
| `release-minor` | Release minor version |
| `release-patch` | Release patch version |

## Localization

TermQ supports 40 languages. All user-facing strings should be localized.

### Adding New Strings

1. Add the key to `Sources/TermQ/Utilities/Strings.swift`:
```swift
enum Settings {
    static let newOption = String(localized: "settings.new.option")
}
```

2. Add the English translation to `Sources/TermQ/Resources/en.lproj/Localizable.strings`:
```
"settings.new.option" = "New Option";
```

3. Add to all other language files (or run the template script):
```bash
./scripts/localization/generate-translations.sh
```

4. Validate all languages have the key:
```bash
./scripts/localization/validate-strings.sh
```

### Translation Workflow

For LLM-assisted translation:
```bash
# Extract strings to JSON
./scripts/localization/extract-to-json.sh > strings.json

# Have Claude translate the JSON, then update the .strings files
```

### Key Files

| File | Purpose |
|------|---------|
| `Sources/TermQ/Utilities/Strings.swift` | Centralized string key definitions |
| `Sources/TermQ/Utilities/SupportedLanguage.swift` | Language picker model |
| `Sources/TermQ/Resources/en.lproj/Localizable.strings` | English (base) translations |
| `Sources/TermQ/Resources/<lang>.lproj/Localizable.strings` | Other language translations |
| `scripts/localization/*.sh` | Translation management scripts |
| `.claude/commands/localization.md` | Claude command for localization tasks |

### Key Naming Convention

Keys follow the pattern: `domain.description.qualifier`
- `board.column.options` - Board domain, column options
- `editor.field.name` - Editor domain, name field
- `settings.section.language` - Settings domain, language section

### Language Support

The app supports all macOS languages including: English, Spanish, French, German, Italian, Portuguese, Dutch, Swedish, Danish, Finnish, Norwegian, Polish, Russian, Ukrainian, Czech, Slovak, Hungarian, Romanian, Croatian, Slovenian, Greek, Turkish, Hebrew, Arabic, Thai, Vietnamese, Indonesian, Malay, Chinese (Simplified, Traditional, Hong Kong), Japanese, Korean, Hindi, and Catalan.

## Dependencies

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) - Terminal emulation
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) - CLI argument parsing
