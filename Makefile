# TermQ Makefile
# Build, test, lint, and manage the project

.PHONY: all build build-release clean test lint format check install uninstall app sign run help
.PHONY: install-cli uninstall-cli install-all uninstall-all
.PHONY: version release release-major release-minor release-patch tag-release

# Version from VERSION file
VERSION := $(shell cat VERSION 2>/dev/null || echo "0.0.0")
MAJOR := $(shell echo $(VERSION) | cut -d. -f1)
MINOR := $(shell echo $(VERSION) | cut -d. -f2)
PATCH := $(shell echo $(VERSION) | cut -d. -f3)

# Default target
all: build

# Build debug version
build:
	swift build

# Build release version
build-release:
	swift build -c release

# Clean build artifacts
clean:
	swift package clean
	rm -rf .build

# Run tests (requires Xcode, not just CommandLineTools)
test:
	swift test

# Install SwiftLint if not present (using Homebrew)
install-swiftlint:
	@which swiftlint > /dev/null || brew install swiftlint

# Install swift-format if not present (using Homebrew)
install-swift-format:
	@which swift-format > /dev/null || brew install swift-format

# Run SwiftLint
lint: install-swiftlint
	swiftlint lint --config .swiftlint.yml

# Run SwiftLint with auto-fix
lint-fix: install-swiftlint
	swiftlint lint --config .swiftlint.yml --fix

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
	cp .build/debug/termq TermQDebug.app/Contents/Resources/termq
	cp TermQ.app/Contents/Info-Debug.plist TermQDebug.app/Contents/Info.plist
	@if [ -f AppIcon.icns ]; then cp AppIcon.icns TermQDebug.app/Contents/Resources/AppIcon.icns; fi
	@echo "Debug app bundle updated at TermQDebug.app (includes termq CLI)"

# Sign the debug app bundle with entitlements
sign: app
	codesign --force --deep --sign - --entitlements TermQ.entitlements TermQDebug.app
	@echo "Debug app signed successfully"

# Build, sign, and run the debug app
run: sign
	@echo "Launching TermQ Debug..."
	@open TermQDebug.app

# Build release app bundle
release-app: build-release
	@mkdir -p TermQ.app/Contents/MacOS
	@mkdir -p TermQ.app/Contents/Resources
	cp .build/release/TermQ TermQ.app/Contents/MacOS/TermQ
	cp .build/release/termq TermQ.app/Contents/Resources/termq
	@if [ -f AppIcon.icns ]; then cp AppIcon.icns TermQ.app/Contents/Resources/AppIcon.icns; fi
	codesign --force --deep --sign - --entitlements TermQ.entitlements TermQ.app
	@echo "Release app bundle created and signed (includes termq CLI)"

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
	cp .build/release/termq /usr/local/bin/termq
	@echo "CLI tool 'termq' installed to /usr/local/bin"

# Uninstall CLI tool
uninstall-cli:
	rm -f /usr/local/bin/termq
	@echo "CLI tool 'termq' removed"

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

# Generate icns from a 1024x1024 PNG (usage: make icon PNG=path/to/icon.png)
icon:
ifndef PNG
	$(error Usage: make icon PNG=path/to/your/1024x1024/icon.png)
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
	@# Update VERSION file
	@echo "$(NEW_VERSION)" > VERSION
	@echo "Updated VERSION file to $(NEW_VERSION)"
	@# Commit the version bump
	@git add VERSION
	@git commit -m "Bump version to $(NEW_VERSION)"
	@echo "Committed version bump"
	@# Create and push the tag
	@git tag -a "v$(NEW_VERSION)" -m "Release v$(NEW_VERSION)"
	@echo "Created tag v$(NEW_VERSION)"
	@echo ""
	@echo "Ready to push. This will trigger the release workflow."
	@read -p "Push to origin? [y/N]: " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		git push origin HEAD && git push origin "v$(NEW_VERSION)"; \
		echo ""; \
		echo "=========================================="
		echo "Release v$(NEW_VERSION) pushed!"; \
		echo "GitHub Actions will now build and publish the release."; \
		echo "==========================================" ; \
	else \
		echo ""; \
		echo "Tag created locally but not pushed."; \
		echo "To push later, run:"; \
		echo "  git push origin HEAD && git push origin v$(NEW_VERSION)"; \
	fi

# Show help
help:
	@echo "TermQ Makefile targets:"
	@echo ""
	@echo "  build         - Build debug version"
	@echo "  build-release - Build release version"
	@echo "  clean         - Clean build artifacts"
	@echo "  test          - Run tests (requires Xcode)"
	@echo "  lint          - Run SwiftLint"
	@echo "  lint-fix      - Run SwiftLint with auto-fix"
	@echo "  format        - Format code with swift-format"
	@echo "  format-check  - Check formatting (CI mode)"
	@echo "  check         - Run all checks (build, lint, format-check, test)"
	@echo "  app           - Build debug app bundle"
	@echo "  sign          - Build and sign debug app bundle"
	@echo "  run           - Build, sign, and launch the app"
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
	@echo ""
	@echo "  help          - Show this help message"
	@echo ""
	@echo "Current version: $(VERSION)"
