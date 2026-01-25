# TermQ Makefile
# Build, test, lint, and manage the project

# Use bash for PIPESTATUS support in build filtering
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

.PHONY: all build-release clean test test.coverage lint format check install uninstall run debug help
.PHONY: install-cli uninstall-cli install-all uninstall-all
.PHONY: version release release-major release-minor release-patch tag-release publish-release
.PHONY: copy-help docs.help

# Project-specific configuration (change these for other projects)
APP_NAME := TermQ
CLI_BINARY := termqcli
MCP_BINARY := termqmcp
DEBUG_APP := $(APP_NAME)Debug.app
DEBUG_APP_NAME := $(APP_NAME)Debug
SOURCE_APP := $(APP_NAME).app
ENTITLEMENTS := $(APP_NAME).entitlements
INFO_PLIST := $(SOURCE_APP)/Contents/Info-Debug.plist
RESOURCES_BUNDLE := $(APP_NAME)_$(APP_NAME).bundle
TEST_BUNDLE := $(APP_NAME)PackageTests

# Build directories (Swift Package Manager conventions)
BUILD_DIR := .build
DEBUG_BUILD_DIR := $(BUILD_DIR)/debug
RELEASE_BUILD_DIR := $(BUILD_DIR)/release

# Installation paths (customize for different systems)
INSTALL_APP_DIR := /Applications
INSTALL_CLI_DIR := /usr/local/bin
XCODE_DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer

# Version from git tags (single source of truth)
# Gets the most recent tag, strips 'v' prefix
VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")
MAJOR := $(shell echo $(VERSION) | cut -d. -f1)
MINOR := $(shell echo $(VERSION) | cut -d. -f2)
PATCH := $(shell echo $(VERSION) | cut -d. -f3)
# Git commit SHA (7 chars)
GIT_SHA := $(shell git rev-parse --short=7 HEAD 2>/dev/null || echo "unknown")

# Track all Swift sources for incremental builds
SWIFT_SOURCES := $(shell find Sources -name "*.swift" 2>/dev/null)
TEST_SOURCES := $(shell find Tests -name "*.swift" 2>/dev/null)

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
	@mkdir -p Sources/$(APP_NAME)/Resources/Help
	@rsync -a --delete Docs/Help/ Sources/$(APP_NAME)/Resources/Help/
	@echo "Help documentation copied to Resources"

# Compile Swift binaries (incremental - only rebuilds if sources or dependencies changed)
$(DEBUG_BUILD_DIR)/$(APP_NAME): $(SWIFT_SOURCES) Package.swift copy-help
	set +o pipefail; swift build -Xswiftc -DDEBUG 2>&1 | $(FILTER_WARNINGS); exit $${PIPESTATUS[0]}

compile: $(DEBUG_BUILD_DIR)/$(APP_NAME)

# Build release version (builds each product explicitly to avoid incremental build issues)
build-release: copy-help
	set +o pipefail; swift build -c release --product $(CLI_BINARY) 2>&1 | $(FILTER_WARNINGS); exit $${PIPESTATUS[0]}
	set +o pipefail; swift build -c release --product $(MCP_BINARY) 2>&1 | $(FILTER_WARNINGS); exit $${PIPESTATUS[0]}
	set +o pipefail; swift build -c release --product $(APP_NAME) 2>&1 | $(FILTER_WARNINGS); exit $${PIPESTATUS[0]}

# Clean build artifacts
clean:
	swift package clean
	rm -rf $(BUILD_DIR)
	rm -rf $(DEBUG_APP)
	rm -rf Sources/$(APP_NAME)/Resources/Help

# Run tests (requires Xcode for XCTest - uses Xcode's developer directory)
test: $(SWIFT_SOURCES) $(TEST_SOURCES) Package.swift copy-help
	DEVELOPER_DIR=$(XCODE_DEVELOPER_DIR) swift test

# Run tests with coverage report
test.coverage: $(SWIFT_SOURCES) $(TEST_SOURCES) Package.swift copy-help
	@echo "Running tests with code coverage..."
	@DEVELOPER_DIR=$(XCODE_DEVELOPER_DIR) swift test --enable-code-coverage
	@echo ""
	@echo "Coverage Report:"
	@echo "================"
	@xcrun llvm-cov report \
		$(DEBUG_BUILD_DIR)/$(TEST_BUNDLE).xctest/Contents/MacOS/$(TEST_BUNDLE) \
		--instr-profile=$(DEBUG_BUILD_DIR)/codecov/default.profdata \
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
	DEVELOPER_DIR=$(XCODE_DEVELOPER_DIR) swiftlint lint --config .swiftlint.yml $(SWIFTLINT_REPORTER)

# Run SwiftLint with auto-fix
lint-fix: install-swiftlint
	DEVELOPER_DIR=$(XCODE_DEVELOPER_DIR) swiftlint lint --config .swiftlint.yml --fix

# Format code with swift-format
format: install-swift-format
	swift-format format --configuration .swift-format --recursive --in-place Sources/ Tests/

# Check formatting (CI mode - doesn't modify files)
format-check: install-swift-format
	swift-format lint --configuration .swift-format --recursive Sources/ Tests/

# Run all checks (compile, lint, format-check, test)
check: compile lint format-check test

# Build the macOS debug app bundle (incremental - only rebuilds if binary or metadata changed)
$(DEBUG_APP): $(DEBUG_BUILD_DIR)/$(APP_NAME) $(INFO_PLIST) $(ENTITLEMENTS)
	@mkdir -p $(DEBUG_APP)/Contents/MacOS
	@mkdir -p $(DEBUG_APP)/Contents/Resources
	@mkdir -p $(DEBUG_APP)/Contents/Frameworks
	cp $(DEBUG_BUILD_DIR)/$(APP_NAME) $(DEBUG_APP)/Contents/MacOS/$(APP_NAME)
	cp $(DEBUG_BUILD_DIR)/$(CLI_BINARY) $(DEBUG_APP)/Contents/Resources/$(CLI_BINARY)
	cp $(DEBUG_BUILD_DIR)/$(MCP_BINARY) $(DEBUG_APP)/Contents/Resources/$(MCP_BINARY)
	cp $(INFO_PLIST) $(DEBUG_APP)/Contents/Info.plist
	@# Add rpath for embedded frameworks (Sparkle)
	@install_name_tool -add_rpath @executable_path/../Frameworks $(DEBUG_APP)/Contents/MacOS/$(APP_NAME) 2>/dev/null || true
	@# Copy Sparkle framework (required for auto-updates)
	@if [ -d "$(DEBUG_BUILD_DIR)/Sparkle.framework" ]; then \
		rm -rf $(DEBUG_APP)/Contents/Frameworks/Sparkle.framework; \
		cp -R $(DEBUG_BUILD_DIR)/Sparkle.framework $(DEBUG_APP)/Contents/Frameworks/; \
	fi
	@# Copy localization resources bundle
	@if [ -d "$(DEBUG_BUILD_DIR)/$(RESOURCES_BUNDLE)" ]; then \
		cp -R $(DEBUG_BUILD_DIR)/$(RESOURCES_BUNDLE) $(DEBUG_APP)/Contents/Resources/; \
	fi
	@# Update version info in Info.plist
	@plutil -replace CFBundleShortVersionString -string "$(VERSION)" $(DEBUG_APP)/Contents/Info.plist
	@plutil -replace CFBundleVersion -string "$(GIT_SHA)" $(DEBUG_APP)/Contents/Info.plist
	@if [ -f AppIcon.icns ]; then cp AppIcon.icns $(DEBUG_APP)/Contents/Resources/AppIcon.icns; fi
	@# Ad-hoc sign for local execution
	@codesign --force --deep --sign - --entitlements $(ENTITLEMENTS) $(DEBUG_APP) 2>/dev/null || \
		codesign --force --deep --sign - $(DEBUG_APP)
	@echo "Debug app bundle ready at $(DEBUG_APP) ($(VERSION) build $(GIT_SHA))"

build: $(DEBUG_APP)

# Build, sign, and run the debug app (auto-quits existing instance)
debug: build
	@if pgrep -f "$(DEBUG_APP)/Contents/MacOS" >/dev/null 2>&1; then \
		echo "Quitting running $(APP_NAME) Debug..."; \
		osascript -e 'tell application "$(DEBUG_APP_NAME)" to quit' 2>/dev/null || true; \
		sleep 1; \
	fi
	@echo "Launching $(APP_NAME) Debug..."
	@open $(DEBUG_APP)

# Build and run the release app (errors if production app is running)
run: release-app
	@if pgrep -f "$(SOURCE_APP)/Contents/MacOS" >/dev/null 2>&1; then \
		echo ""; \
		echo "Error: $(APP_NAME) (Production) is already running."; \
		echo "Please quit it manually before running 'make run'."; \
		echo ""; \
		exit 1; \
	fi
	@echo "Launching $(APP_NAME) (Release)..."
	@open $(SOURCE_APP)

# Build release app bundle
release-app: build-release
	@mkdir -p $(SOURCE_APP)/Contents/MacOS
	@mkdir -p $(SOURCE_APP)/Contents/Resources
	@mkdir -p $(SOURCE_APP)/Contents/Frameworks
	@# Verify GUI binary is correct (should be >4MB, CLI is only ~2MB)
	@SIZE=$$(stat -f%z $(RELEASE_BUILD_DIR)/$(APP_NAME)); \
	if [ $$SIZE -lt 4000000 ]; then \
		echo "ERROR: $(APP_NAME) binary is too small ($$SIZE bytes) - likely CLI instead of GUI"; \
		echo "Try: rm -rf $(RELEASE_BUILD_DIR) && make build-release"; \
		exit 1; \
	fi
	cp $(RELEASE_BUILD_DIR)/$(APP_NAME) $(SOURCE_APP)/Contents/MacOS/$(APP_NAME)
	cp $(RELEASE_BUILD_DIR)/$(CLI_BINARY) $(SOURCE_APP)/Contents/Resources/$(CLI_BINARY)
	cp $(RELEASE_BUILD_DIR)/$(MCP_BINARY) $(SOURCE_APP)/Contents/Resources/$(MCP_BINARY)
	@# Add rpath for embedded frameworks (Sparkle)
	@install_name_tool -add_rpath @executable_path/../Frameworks $(SOURCE_APP)/Contents/MacOS/$(APP_NAME) 2>/dev/null || true
	@# Copy Sparkle framework (required for auto-updates)
	@if [ -d "$(RELEASE_BUILD_DIR)/Sparkle.framework" ]; then \
		rm -rf $(SOURCE_APP)/Contents/Frameworks/Sparkle.framework; \
		cp -R $(RELEASE_BUILD_DIR)/Sparkle.framework $(SOURCE_APP)/Contents/Frameworks/; \
	fi
	@# Copy localization resources bundle
	@if [ -d "$(RELEASE_BUILD_DIR)/$(RESOURCES_BUNDLE)" ]; then \
		cp -R $(RELEASE_BUILD_DIR)/$(RESOURCES_BUNDLE) $(SOURCE_APP)/Contents/Resources/; \
	fi
	@# Copy template and update version info in Info.plist
	cp Info.plist.template $(SOURCE_APP)/Contents/Info.plist
	@plutil -replace CFBundleShortVersionString -string "$(VERSION)" $(SOURCE_APP)/Contents/Info.plist
	@plutil -replace CFBundleVersion -string "$(GIT_SHA)" $(SOURCE_APP)/Contents/Info.plist
	@if [ -f AppIcon.icns ]; then cp AppIcon.icns $(SOURCE_APP)/Contents/Resources/AppIcon.icns; fi
	codesign --force --deep --sign - --entitlements $(ENTITLEMENTS) $(SOURCE_APP)
	@echo "Release app bundle created and signed ($(VERSION) build $(GIT_SHA))"

# Install app
install: release-app
	@echo "Installing $(SOURCE_APP) to $(INSTALL_APP_DIR)..."
	@rm -rf $(INSTALL_APP_DIR)/$(SOURCE_APP)
	cp -R $(SOURCE_APP) $(INSTALL_APP_DIR)/
	@echo "$(SOURCE_APP) installed to $(INSTALL_APP_DIR)"
	@echo "You may need to restart any running instance"

# Uninstall app
uninstall:
	@echo "Removing $(SOURCE_APP) from $(INSTALL_APP_DIR)..."
	rm -rf $(INSTALL_APP_DIR)/$(SOURCE_APP)
	@echo "$(SOURCE_APP) removed"

# Install CLI tool
install-cli: build-release
	@mkdir -p $(INSTALL_CLI_DIR)
	cp $(RELEASE_BUILD_DIR)/$(CLI_BINARY) $(INSTALL_CLI_DIR)/$(CLI_BINARY)
	@echo "CLI tool '$(CLI_BINARY)' installed to $(INSTALL_CLI_DIR)"

# Uninstall CLI tool
uninstall-cli:
	rm -f $(INSTALL_CLI_DIR)/$(CLI_BINARY)
	@echo "CLI tool '$(CLI_BINARY)' removed"

# Install both app and CLI
install-all: install install-cli
	@echo "TermQ app and CLI installed"

# Uninstall both app and CLI
uninstall-all: uninstall uninstall-cli
	@echo "TermQ app and CLI removed"

# Create a distributable DMG (requires create-dmg tool)
dmg: release-app
	@which create-dmg > /dev/null || (echo "Install create-dmg: brew install create-dmg" && exit 1)
	rm -f $(APP_NAME).dmg
	create-dmg \
		--volname "$(APP_NAME)" \
		--window-pos 200 120 \
		--window-size 600 400 \
		--icon-size 100 \
		--icon "$(SOURCE_APP)" 150 185 \
		--hide-extension "$(SOURCE_APP)" \
		--app-drop-link 450 185 \
		"$(APP_NAME).dmg" \
		"$(SOURCE_APP)"
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
	@ln -s $(INSTALL_APP_DIR) dmg-contents/Applications
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
	@echo "  install       - Build release and install app to $(INSTALL_APP_DIR)"
	@echo "  uninstall     - Remove app from $(INSTALL_APP_DIR)"
	@echo "  install-cli   - Install CLI tool to $(INSTALL_CLI_DIR)"
	@echo "  uninstall-cli - Remove CLI tool from $(INSTALL_CLI_DIR)"
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
