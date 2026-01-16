# TermQ Makefile
# Build, test, lint, and manage the project

# Use bash for PIPESTATUS support in build filtering
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

.PHONY: all build build-release clean test test.coverage lint format check install uninstall app sign run debug help
.PHONY: install-cli uninstall-cli install-all uninstall-all
.PHONY: version release release-major release-minor release-patch tag-release publish-release
.PHONY: copy-help docs.help

# Version from git tags (single source of truth)
# Gets the most recent tag, strips 'v' prefix
VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")
MAJOR := $(shell echo $(VERSION) | cut -d. -f1)
MINOR := $(shell echo $(VERSION) | cut -d. -f2)
PATCH := $(shell echo $(VERSION) | cut -d. -f3)
# Git commit SHA (7 chars)
GIT_SHA := $(shell git rev-parse --short=7 HEAD 2>/dev/null || echo "unknown")

# CI environment detection - enables GitHub-specific features when running in CI
# GitHub Actions sets CI=true automatically
SWIFTLINT_REPORTER := $(if $(CI),--reporter github-actions-logging,)

# =============================================================================
# Build Warning Filters
# =============================================================================
# These patterns filter harmless warnings from third-party dependencies.
# We can't fix these - they come from upstream packages we don't control.
# Add new patterns as needed, using -e "pattern" for each.
#
# To test a pattern: swift build 2>&1 | grep "your pattern"
# To disable filtering temporarily: make build-release FILTER_WARNINGS=cat
# =============================================================================
FILTER_WARNINGS = grep -v \
	-e "'swiftterm': found .* unhandled" \
	-e "checkouts/SwiftTerm.*README.md" \
	-e "process_shims.h" \
	-e "<module-includes>" \
	-e "pointer is missing a nullability type specifier" \
	-e "target_conditionals.h" \
	-e "_Nonnull" \
	-e "_Nullable" \
	-e "_subprocess_pthread" \
	-e "^ *[0-9]* | *$$"
# Filter explanations:
#   'swiftterm': found .* unhandled / checkouts/SwiftTerm.*README.md
#       SwiftTerm has a README.md not declared as a resource - cosmetic only
#   process_shims.h / <module-includes> / target_conditionals.h
#       File path noise from swift-subprocess C shim headers
#   pointer is missing a nullability type specifier / _Nonnull / _Nullable / _subprocess_pthread
#       Clang warning about ObjC nullability in Apple's swift-subprocess
#   ^ *[0-9]* | *$$
#       Empty code context lines (e.g., " 42 | ") from Clang warnings

# Default target
all: build

# Copy help documentation to Resources (must run before swift build)
copy-help:
	@mkdir -p Sources/TermQ/Resources/Help
	@rsync -a --delete Docs/Help/ Sources/TermQ/Resources/Help/
	@echo "Help documentation copied to Resources"

# Build debug version (with DEBUG flag for conditional compilation)
build: copy-help
	set +o pipefail; swift build -Xswiftc -DDEBUG 2>&1 | $(FILTER_WARNINGS); exit $${PIPESTATUS[0]}

# Build release version (builds each product explicitly to avoid incremental build issues)
build-release: copy-help
	set +o pipefail; swift build -c release --product termqcli 2>&1 | $(FILTER_WARNINGS); exit $${PIPESTATUS[0]}
	set +o pipefail; swift build -c release --product termqmcp 2>&1 | $(FILTER_WARNINGS); exit $${PIPESTATUS[0]}
	set +o pipefail; swift build -c release --product TermQ 2>&1 | $(FILTER_WARNINGS); exit $${PIPESTATUS[0]}

# Clean build artifacts
clean:
	swift package clean
	rm -rf .build
	rm -rf Sources/TermQ/Resources/Help

# Run tests (requires Xcode for XCTest - uses Xcode's developer directory)
test: copy-help
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# Run tests with coverage report
test.coverage: copy-help
	@echo "Running tests with code coverage..."
	@DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --enable-code-coverage
	@echo ""
	@echo "Coverage Report:"
	@echo "================"
	@xcrun llvm-cov report \
		.build/debug/TermQPackageTests.xctest/Contents/MacOS/TermQPackageTests \
		--instr-profile=.build/debug/codecov/default.profdata \
		--sources Sources/

# Install SwiftLint if not present (using Homebrew)
install-swiftlint:
	@which swiftlint > /dev/null || brew install swiftlint

# Install swift-format if not present (using Homebrew)
install-swift-format:
	@which swift-format > /dev/null || brew install swift-format

# Run SwiftLint (auto-detects CI for GitHub annotations)
# Requires Xcode for SourceKit - uses Xcode's developer directory
lint: install-swiftlint
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftlint lint --config .swiftlint.yml $(SWIFTLINT_REPORTER)

# Run SwiftLint with auto-fix
lint-fix: install-swiftlint
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftlint lint --config .swiftlint.yml --fix

# Format code with swift-format
format: install-swift-format
	swift-format format --configuration .swift-format --recursive --in-place Sources/ Tests/

# Check formatting (CI mode - doesn't modify files)
format-check: install-swift-format
	swift-format lint --configuration .swift-format --recursive Sources/ Tests/

# Run all checks (build, lint, format-check, test)
check: build lint format-check test

# Build the macOS debug app bundle (separate from release)
app: build
	@mkdir -p TermQDebug.app/Contents/MacOS
	@mkdir -p TermQDebug.app/Contents/Resources
	cp .build/debug/TermQ TermQDebug.app/Contents/MacOS/TermQ
	cp .build/debug/termqcli TermQDebug.app/Contents/Resources/termqcli
	cp .build/debug/termqmcp TermQDebug.app/Contents/Resources/termqmcp
	cp TermQ.app/Contents/Info-Debug.plist TermQDebug.app/Contents/Info.plist
	@# Copy localization resources bundle
	@if [ -d ".build/debug/TermQ_TermQ.bundle" ]; then \
		cp -R .build/debug/TermQ_TermQ.bundle TermQDebug.app/Contents/Resources/; \
	fi
	@# Update version info in Info.plist
	@plutil -replace CFBundleShortVersionString -string "$(VERSION)" TermQDebug.app/Contents/Info.plist
	@plutil -replace CFBundleVersion -string "$(GIT_SHA)" TermQDebug.app/Contents/Info.plist
	@if [ -f AppIcon.icns ]; then cp AppIcon.icns TermQDebug.app/Contents/Resources/AppIcon.icns; fi
	@echo "Debug app bundle updated at TermQDebug.app ($(VERSION) build $(GIT_SHA))"

# Sign the debug app bundle with entitlements
sign: app
	codesign --force --deep --sign - --entitlements TermQ.entitlements TermQDebug.app
	@echo "Debug app signed successfully"

# Build, sign, and run the debug app (auto-quits existing instance)
debug: sign
	@if pgrep -f "TermQDebug.app/Contents/MacOS" >/dev/null 2>&1; then \
		echo "Quitting running TermQ Debug..."; \
		osascript -e 'tell application "TermQDebug" to quit' 2>/dev/null || true; \
		sleep 1; \
	fi
	@echo "Launching TermQ Debug..."
	@open TermQDebug.app

# Build and run the release app (errors if production app is running)
run: release-app
	@if pgrep -f "TermQ.app/Contents/MacOS" >/dev/null 2>&1; then \
		echo ""; \
		echo "Error: TermQ (Production) is already running."; \
		echo "Please quit it manually before running 'make run'."; \
		echo ""; \
		exit 1; \
	fi
	@echo "Launching TermQ (Release)..."
	@open TermQ.app

# Build release app bundle
release-app: build-release
	@mkdir -p TermQ.app/Contents/MacOS
	@mkdir -p TermQ.app/Contents/Resources
	@# Verify GUI binary is correct (should be >4MB, CLI is only ~2MB)
	@SIZE=$$(stat -f%z .build/release/TermQ); \
	if [ $$SIZE -lt 4000000 ]; then \
		echo "ERROR: TermQ binary is too small ($$SIZE bytes) - likely CLI instead of GUI"; \
		echo "Try: rm -rf .build/release && make build-release"; \
		exit 1; \
	fi
	cp .build/release/TermQ TermQ.app/Contents/MacOS/TermQ
	cp .build/release/termqcli TermQ.app/Contents/Resources/termqcli
	cp .build/release/termqmcp TermQ.app/Contents/Resources/termqmcp
	@# Copy localization resources bundle
	@if [ -d ".build/release/TermQ_TermQ.bundle" ]; then \
		cp -R .build/release/TermQ_TermQ.bundle TermQ.app/Contents/Resources/; \
	fi
	@# Copy template and update version info in Info.plist
	cp Info.plist.template TermQ.app/Contents/Info.plist
	@plutil -replace CFBundleShortVersionString -string "$(VERSION)" TermQ.app/Contents/Info.plist
	@plutil -replace CFBundleVersion -string "$(GIT_SHA)" TermQ.app/Contents/Info.plist
	@if [ -f AppIcon.icns ]; then cp AppIcon.icns TermQ.app/Contents/Resources/AppIcon.icns; fi
	codesign --force --deep --sign - --entitlements TermQ.entitlements TermQ.app
	@echo "Release app bundle created and signed ($(VERSION) build $(GIT_SHA))"

# Install app to /Applications
install: release-app
	@echo "Installing TermQ.app to /Applications..."
	@rm -rf /Applications/TermQ.app
	cp -R TermQ.app /Applications/
	@echo "TermQ.app installed to /Applications"
	@echo "You may need to restart any running instance"

# Uninstall app from /Applications
uninstall:
	@echo "Removing TermQ.app from /Applications..."
	rm -rf /Applications/TermQ.app
	@echo "TermQ.app removed"

# Install CLI tool to /usr/local/bin
install-cli: build-release
	@mkdir -p /usr/local/bin
	cp .build/release/termqcli /usr/local/bin/termqcli
	@echo "CLI tool 'termqcli' installed to /usr/local/bin"

# Uninstall CLI tool
uninstall-cli:
	rm -f /usr/local/bin/termqcli
	@echo "CLI tool 'termqcli' removed"

# Install both app and CLI
install-all: install install-cli
	@echo "TermQ app and CLI installed"

# Uninstall both app and CLI
uninstall-all: uninstall uninstall-cli
	@echo "TermQ app and CLI removed"

# Create a distributable DMG (requires create-dmg tool)
dmg: release-app
	@which create-dmg > /dev/null || (echo "Install create-dmg: brew install create-dmg" && exit 1)
	rm -f TermQ.dmg
	create-dmg \
		--volname "TermQ" \
		--window-pos 200 120 \
		--window-size 600 400 \
		--icon-size 100 \
		--icon "TermQ.app" 150 185 \
		--hide-extension "TermQ.app" \
		--app-drop-link 450 185 \
		"TermQ.dmg" \
		"TermQ.app"
	@echo "DMG created: TermQ.dmg"

# Create a zip archive for distribution
zip: release-app
	rm -f TermQ.zip
	zip -r TermQ.zip TermQ.app
	@echo "Archive created: TermQ.zip"

# Generate icns from a 1024x1024 PNG (usage: make icon PNG=./Assets/icon.png)
icon:
ifndef PNG
	$(error Usage: make icon PNG=./Assets/icon.png)
endif
	@echo "Generating AppIcon.icns from $(PNG)..."
	@mkdir -p AppIcon.iconset
	@sips -z 16 16     $(PNG) --out AppIcon.iconset/icon_16x16.png
	@sips -z 32 32     $(PNG) --out AppIcon.iconset/icon_16x16@2x.png
	@sips -z 32 32     $(PNG) --out AppIcon.iconset/icon_32x32.png
	@sips -z 64 64     $(PNG) --out AppIcon.iconset/icon_32x32@2x.png
	@sips -z 128 128   $(PNG) --out AppIcon.iconset/icon_128x128.png
	@sips -z 256 256   $(PNG) --out AppIcon.iconset/icon_128x128@2x.png
	@sips -z 256 256   $(PNG) --out AppIcon.iconset/icon_256x256.png
	@sips -z 512 512   $(PNG) --out AppIcon.iconset/icon_256x256@2x.png
	@sips -z 512 512   $(PNG) --out AppIcon.iconset/icon_512x512.png
	@sips -z 1024 1024 $(PNG) --out AppIcon.iconset/icon_512x512@2x.png
	@iconutil -c icns AppIcon.iconset -o AppIcon.icns
	@rm -rf AppIcon.iconset
	@echo "Created AppIcon.icns"
	@# Clear macOS icon cache
	@touch TermQ.app 2>/dev/null || true
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f TermQ.app 2>/dev/null || true
	@sudo rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
	@killall Finder Dock 2>/dev/null || true
	@echo "Icon cache cleared"
	@echo "Run 'make sign' to rebuild the app with the new icon"

# Show current version
version:
	@echo "Current version: $(VERSION)"
	@echo "  Major: $(MAJOR)"
	@echo "  Minor: $(MINOR)"
	@echo "  Patch: $(PATCH)"

# Interactive release - asks for version bump type
release:
	@echo "Current version: $(VERSION)"
	@echo ""
	@echo "Select release type:"
	@echo "  1) patch  ($(MAJOR).$(MINOR).$$(($(PATCH)+1))) - Bug fixes, minor changes"
	@echo "  2) minor  ($(MAJOR).$$(($(MINOR)+1)).0) - New features, backwards compatible"
	@echo "  3) major  ($$(($(MAJOR)+1)).0.0) - Breaking changes"
	@echo ""
	@read -p "Enter choice [1-3]: " choice; \
	case $$choice in \
		1) $(MAKE) release-patch ;; \
		2) $(MAKE) release-minor ;; \
		3) $(MAKE) release-major ;; \
		*) echo "Invalid choice. Aborting."; exit 1 ;; \
	esac

# Release a new major version (x.0.0)
release-major:
	@NEW_VERSION="$$(($(MAJOR)+1)).0.0"; \
	$(MAKE) tag-release NEW_VERSION=$$NEW_VERSION

# Release a new minor version (x.y.0)
release-minor:
	@NEW_VERSION="$(MAJOR).$$(($(MINOR)+1)).0"; \
	$(MAKE) tag-release NEW_VERSION=$$NEW_VERSION

# Release a new patch version (x.y.z)
release-patch:
	@NEW_VERSION="$(MAJOR).$(MINOR).$$(($(PATCH)+1))"; \
	$(MAKE) tag-release NEW_VERSION=$$NEW_VERSION

# Internal target to create and push a release tag
# Version is derived entirely from git tags - no VERSION file needed
tag-release:
ifndef NEW_VERSION
	$(error NEW_VERSION is not set)
endif
	@echo ""
	@echo "=========================================="
	@echo "Releasing version $(NEW_VERSION)"
	@echo "=========================================="
	@echo ""
	@# Check for uncommitted changes
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "Error: You have uncommitted changes."; \
		echo "Please commit or stash them before releasing."; \
		git status --short; \
		exit 1; \
	fi
	@# Check we're on main/master branch
	@BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	if [ "$$BRANCH" != "main" ] && [ "$$BRANCH" != "master" ]; then \
		echo "Warning: You're on branch '$$BRANCH', not main/master."; \
		read -p "Continue anyway? [y/N]: " confirm; \
		if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
			echo "Aborting."; \
			exit 1; \
		fi; \
	fi
	@# Create the tag (this IS the version - single source of truth)
	@git tag -a "v$(NEW_VERSION)" -m "Release v$(NEW_VERSION)"
	@echo "Created tag v$(NEW_VERSION)"
	@echo ""
	@echo "Ready to push. This will trigger the release workflow."
	@read -p "Push tag to origin? [y/N]: " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		git push origin "v$(NEW_VERSION)"; \
		echo ""; \
		echo "=========================================="; \
		echo "Release v$(NEW_VERSION) pushed!"; \
		echo "GitHub Actions will now build and publish the release."; \
		echo "=========================================="; \
	else \
		echo ""; \
		echo "Tag created locally but not pushed."; \
		echo "To push later, run:"; \
		echo "  git push origin v$(NEW_VERSION)"; \
	fi

# Publish a release to GitHub (manual release when CI is unavailable)
# Usage: make publish-release
# This creates release artifacts and publishes them to GitHub
publish-release: release-app
	@echo ""
	@echo "=========================================="
	@echo "Publishing release v$(VERSION)"
	@echo "=========================================="
	@echo ""
	@# Check gh CLI is installed
	@which gh > /dev/null || (echo "Error: GitHub CLI (gh) not installed. Run: brew install gh" && exit 1)
	@# Check gh is authenticated
	@gh auth status > /dev/null 2>&1 || (echo "Error: Not authenticated with GitHub CLI. Run: gh auth login" && exit 1)
	@# Create release artifacts
	@echo "Creating release artifacts..."
	@rm -f TermQ-$(VERSION).dmg TermQ-$(VERSION).zip checksums.txt
	@# Create DMG
	@mkdir -p dmg-contents
	@cp -R TermQ.app dmg-contents/
	@ln -s /Applications dmg-contents/Applications
	@hdiutil create -volname "TermQ" -srcfolder dmg-contents -ov -format UDZO TermQ-$(VERSION).dmg
	@rm -rf dmg-contents
	@echo "Created: TermQ-$(VERSION).dmg"
	@# Create zip
	@zip -r TermQ-$(VERSION).zip TermQ.app
	@echo "Created: TermQ-$(VERSION).zip"
	@# Generate checksums
	@shasum -a 256 TermQ-$(VERSION).dmg > checksums.txt
	@shasum -a 256 TermQ-$(VERSION).zip >> checksums.txt
	@echo "Created: checksums.txt"
	@cat checksums.txt
	@echo ""
	@# Check if tag exists, create if not
	@if ! git tag -l "v$(VERSION)" | grep -q .; then \
		echo "Creating tag v$(VERSION)..."; \
		git tag -a "v$(VERSION)" -m "Release v$(VERSION)"; \
		git push origin "v$(VERSION)"; \
	else \
		echo "Tag v$(VERSION) already exists"; \
	fi
	@echo ""
	@echo "Creating GitHub release..."
	@gh release create "v$(VERSION)" \
		--title "TermQ v$(VERSION)" \
		--generate-notes \
		TermQ-$(VERSION).dmg \
		TermQ-$(VERSION).zip \
		checksums.txt
	@echo ""
	@echo "=========================================="
	@echo "Release v$(VERSION) published!"
	@echo "=========================================="
	@# Cleanup local artifacts
	@rm -f TermQ-$(VERSION).dmg TermQ-$(VERSION).zip checksums.txt

# Worktree Management
worktree:
	@BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	if [ "$$BRANCH" = "main" ]; then \
		echo "Error: Create a feature branch first: git checkout -b <branch>"; \
		exit 1; \
	fi; \
	if [ -n "$$(git status --porcelain)" ]; then \
		echo "Error: Uncommitted changes. Commit or stash first."; \
		exit 1; \
	fi; \
	git worktree prune; \
	git checkout main; \
	git worktree add ../TermQ-$$BRANCH $$BRANCH; \
	echo "Worktree created: ../TermQ-$$BRANCH"

worktree.update:
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "Error: Uncommitted changes. Commit or stash first."; \
		exit 1; \
	fi; \
	BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	git fetch origin; \
	if [ "$$BRANCH" = "main" ]; then \
		git pull origin main; \
	else \
		git rebase origin/main || { echo "Resolve conflicts, then: git rebase --continue"; exit 1; }; \
	fi

worktree.delete:
	@GIT_DIR=$$(git rev-parse --git-dir 2>/dev/null); \
	GIT_COMMON=$$(git rev-parse --git-common-dir 2>/dev/null); \
	if [ "$$GIT_DIR" = "$$GIT_COMMON" ] || [ "$$GIT_DIR" = ".git" ]; then \
		echo "Error: Not in a worktree."; \
		exit 1; \
	fi; \
	if [ -n "$$(git status --porcelain)" ]; then \
		echo "Error: Uncommitted changes. Commit or stash first."; \
		exit 1; \
	fi; \
	BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	git fetch origin; \
	LOCAL=$$(git rev-parse HEAD); \
	REMOTE=$$(git rev-parse origin/$$BRANCH 2>/dev/null || echo ""); \
	if [ -z "$$REMOTE" ]; then \
		echo "Error: Branch not on remote. Push first: git push -u origin $$BRANCH"; \
		exit 1; \
	fi; \
	if [ "$$LOCAL" != "$$REMOTE" ]; then \
		echo "Error: Not synced with remote. Push or pull first."; \
		exit 1; \
	fi; \
	WORKTREE=$$(basename $$(pwd)); \
	read -p "Delete worktree '$$WORKTREE'? [y/N] " CONFIRM; \
	if [ "$$CONFIRM" != "y" ] && [ "$$CONFIRM" != "Y" ]; then exit 1; fi; \
	cd .. && rm -rf "$$WORKTREE" && cd TermQ && \
	git pull && git worktree prune; \
	echo "Worktree deleted: $$WORKTREE"


# Serve help documentation with docsify (live reload)
docs.help:
	@echo "Starting docsify server for Help documentation..."
	@echo "Press Ctrl+C to stop"
	@if lsof -i :3000 >/dev/null 2>&1; then \
		echo "Port 3000 in use, using random port..."; \
		npx docsify-cli serve Docs/Help; \
	else \
		npx docsify-cli serve Docs/Help --port 3000; \
	fi

# Show help
help:
	@echo "TermQ Makefile targets:"
	@echo ""
	@echo "  copy-help     - Copy help docs from Docs/Help to Resources"
	@echo "  build         - Build debug version (runs copy-help first)"
	@echo "  build-release - Build release version"
	@echo "  clean         - Clean build artifacts"
	@echo "  test          - Run tests (requires Xcode)"
	@echo "  test.coverage - Run tests with coverage report"
	@echo "  lint          - Run SwiftLint"
	@echo "  lint-fix      - Run SwiftLint with auto-fix"
	@echo "  format        - Format code with swift-format"
	@echo "  format-check  - Check formatting (CI mode)"
	@echo "  check         - Run all checks (build, lint, format-check, test)"
	@echo "  app           - Build debug app bundle"
	@echo "  sign          - Build and sign debug app bundle"
	@echo "  run           - Build release and launch TermQ.app"
	@echo "  debug         - Build debug and launch TermQDebug.app"
	@echo "  release-app   - Build and sign release app bundle"
	@echo "  install       - Build release and install app to /Applications"
	@echo "  uninstall     - Remove app from /Applications"
	@echo "  install-cli   - Install CLI tool to /usr/local/bin"
	@echo "  uninstall-cli - Remove CLI tool from /usr/local/bin"
	@echo "  install-all   - Install both app and CLI"
	@echo "  uninstall-all - Remove both app and CLI"
	@echo "  dmg           - Create distributable DMG"
	@echo "  zip           - Create distributable zip archive"
	@echo "  icon          - Generate AppIcon.icns from PNG (make icon PNG=path/to/icon.png)"
	@echo ""
	@echo "  version       - Show current version"
	@echo "  release       - Interactive release (asks for major/minor/patch)"
	@echo "  release-major - Release new major version ($(MAJOR).x.x -> $$(($(MAJOR)+1)).0.0)"
	@echo "  release-minor - Release new minor version (x.$(MINOR).x -> x.$$(($(MINOR)+1)).0)"
	@echo "  release-patch - Release new patch version (x.x.$(PATCH) -> x.x.$$(($(PATCH)+1)))"
	@echo "  publish-release - Build and publish release to GitHub (manual release)"
	@echo ""
	@echo "  Worktree:     - worktree worktree.update worktree.delete"
	@echo ""
	@echo "  docs.help     - Serve Help docs with docsify (live reload)"
	@echo "  help          - Show this help message"
	@echo ""
	@echo "Current version: $(VERSION)"
