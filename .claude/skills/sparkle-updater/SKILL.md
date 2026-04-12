---
name: sparkle-updater
description: Sparkle auto-update system for TermQ. Load when working on release workflows, appcast generation, update signing, or debugging update failures. Covers the full update pipeline from signing through delivery.
---

# Sparkle Updater System

## Architecture

The auto-update pipeline has five stages. A failure at ANY stage breaks updates silently:

```
Build & Sign → ZIP Archive → EdDSA Sign → GitHub Release → Appcast → User Update
     CI           CI            CI            CI             CI        Sparkle
```

## Critical Rules

### 1. ALWAYS use `ditto` for ZIP creation, NEVER `zip`

```bash
# CORRECT — preserves symlinks and macOS extended attributes
ditto -c -k --keepParent TermQ.app TermQ-VERSION.zip

# WRONG — dereferences symlinks, breaks framework code signatures
zip -r TermQ-VERSION.zip TermQ.app      # DO NOT USE
zip -r -y TermQ-VERSION.zip TermQ.app   # -y helps but ditto is safer
```

**Why:** Sparkle.framework uses a versioned structure with symlinks (`Versions/Current -> B`, top-level `Sparkle -> Versions/Current/Sparkle`, etc.). `zip -r` follows symlinks and stores full copies, creating 3x duplicates and destroying the framework structure. When Sparkle extracts this ZIP, `codesign --verify` fails with "bundle format is ambiguous" and the update is rejected.

**How to verify:** After creating the ZIP, extract it and run:
```bash
ls -la TermQ.app/Contents/Frameworks/Sparkle.framework/
# Top-level items MUST be symlinks (l at start of ls -la)
# If they show as regular files (-) or directories (d), the ZIP is broken

codesign --verify --deep --strict --verbose=2 TermQ.app
# Must exit 0 with no errors
```

### 2. Sign Sparkle components inside-out, NEVER use `--deep`

```bash
# Sign XPC services first
for xpc in "$SPARKLE/XPCServices/"*.xpc; do
  codesign --force --options runtime --timestamp \
    --sign "$IDENTITY" --keychain "$KEYCHAIN" "$xpc"
done

# Then Updater.app helper
codesign --force --options runtime --timestamp \
  --sign "$IDENTITY" --keychain "$KEYCHAIN" "$SPARKLE/Updater.app"

# Then Autoupdate binary
codesign --force --options runtime --timestamp \
  --sign "$IDENTITY" --keychain "$KEYCHAIN" "$SPARKLE/Autoupdate"

# Then framework itself (last, no --deep)
codesign --force --options runtime --timestamp \
  --sign "$IDENTITY" --keychain "$KEYCHAIN" "$SPARKLE"

# Finally sign the main app bundle
codesign --force --options runtime --timestamp \
  --sign "$IDENTITY" --keychain "$KEYCHAIN" \
  --entitlements TermQ.entitlements TermQ.app
```

**Why:** `--deep` overrides each component's own entitlements and breaks the XPC trust chain. The Installer.xpc and Downloader.xpc services need their own signing identity. Using `--deep` causes "An error occurred while running the updater" at install time.

### 3. EdDSA signing uses Sparkle's `sign_update` tool

```bash
SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"
echo "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - -p "$ZIP"
```

- `--ed-key-file -` reads the private key from stdin
- `-p` outputs only the raw base64 signature (no XML wrapping)
- The `.sig` file must be uploaded as a GitHub Release asset
- The appcast generator fetches it and embeds it in the XML

### 5. `CFBundleVersion` and `sparkle:version` MUST use the same dot-notation format

Sparkle's `SUStandardVersionComparator` **truncates version strings at the first dash** (`SUStandardVersionComparator.m:114-115`). This means `0.7.0-beta.8` and `0.7.0-beta.9` both truncate to `0.7.0` and compare as equal — no update is ever offered between consecutive beta releases.

**The single canonical format everywhere:**

| Release | Git tag (GitHub) | App version (everywhere else) |
|---|---|---|
| beta | `v0.7.0-beta.9` | `0.7.0.b9` |
| alpha | `v0.7.0-alpha.3` | `0.7.0.a3` |
| rc | `v0.7.0-rc.2` | `0.7.0.rc2` |
| stable | `v0.7.0` | `0.7.0` |

The conversion is applied in three places (all must stay in sync):
- `Makefile`: `SPARKLE_VERSION := $(shell echo "$(VERSION)" | sed 's/-beta\./.b/;s/-alpha\./.a/;s/-rc\./.rc/')`
- `scripts/generate-appcast.sh`: `sparkle_version()` function
- `.github/workflows/release.yml`: inline `sed` in the "Create app bundle" step

Both `CFBundleVersion` and `CFBundleShortVersionString` use this dot-notation format. The git SHA is stored in the **custom key `TermQBuildSHA`** (display only — Sparkle never reads custom keys).

**If `CFBundleVersion` contains a git SHA** (like `8be83a1`), Sparkle's comparator interprets the leading hex digit numerically — `8... > 0.7.0` — so the installed app always appears newer than any appcast entry. No update is ever offered.

### 4. GitHub release asset URLs require redirect following

```bash
# GitHub returns 302 to CDN — MUST use -L
curl -sSL "$sig_url"

# Without -L, you get empty content or HTML error page
curl -sS "$sig_url"   # WRONG — gets 302 body (empty)
```

## Component Map

| Component | Location | Purpose |
|---|---|---|
| Release workflow | `.github/workflows/release.yml` | Build, sign, notarize, create ZIP, publish |
| Appcast workflow | `.github/workflows/update-appcast.yml` | Generate appcast XML from GitHub Releases API |
| Appcast generator | `scripts/generate-appcast.sh` | Fetch releases, signatures, generate XML |
| Stable appcast | `Docs/appcast.xml` | Stable channel feed (GitHub Pages) |
| Beta appcast | `Docs/appcast-beta.xml` | All releases including pre-releases |
| Info.plist template | `Info.plist.template` | `SUFeedURL`, `SUPublicEDKey`, update settings |
| Feed URL delegate | `Sources/TermQ/TermQApp.swift` (SparkleUpdaterDelegate) | Runtime feed selection (stable vs beta) |
| Sparkle dependency | `Package.swift` | `sparkle-project/Sparkle` from: `2.6.0` |
| sign_update tool | `.build/artifacts/sparkle/Sparkle/bin/sign_update` | EdDSA signing/verification |

## GitHub Secrets

| Secret | Purpose |
|---|---|
| `APPLE_CERTIFICATE_BASE64` | Developer ID Application certificate (P12) |
| `APPLE_CERTIFICATE_PASSWORD` | Certificate import password |
| `APPLE_ID` | Apple ID for notarization |
| `APPLE_TEAM_ID` | Apple Team ID |
| `APPLE_APP_PASSWORD` | App-specific password for notarization |
| `SPARKLE_PRIVATE_KEY` | EdDSA private key for update signing |
| `APPCAST_TOKEN` | GitHub PAT for appcast commit to main |

## Keys

- **Public key** (in Info.plist): `SUPublicEDKey` — base64-encoded Ed25519 public key (32 bytes)
- **Private key** (GitHub secret): `SPARKLE_PRIVATE_KEY` — used by `sign_update` to generate EdDSA signatures
- These MUST be a matching pair. Generated once with `generate_keys` tool. If regenerated, ALL existing signed releases become unverifiable.

## Update Flow (What Sparkle Does)

```
1. App checks feed URL (eyelock.github.io/TermQ/appcast[-beta].xml)
2. Parses XML, finds newest version > installed version
3. Downloads ZIP from GitHub Releases (follows 302 redirect to CDN)
4. Verifies EdDSA signature: sign(ZIP bytes) matches sparkle:edSignature
5. Extracts ZIP archive
6. Verifies code signature of extracted .app bundle (codesign --verify)
7. Launches Installer.xpc to replace running app
8. Restarts
```

Failure at step 4 = bad/missing signature. Failure at step 6 = broken archive (symlinks, signing). Failure at step 7 = XPC signing issue.

## Verification Checklist

Before declaring a release workflow change complete, verify ALL of these:

1. **Version format:** `plutil -p TermQ.app/Contents/Info.plist | grep -E "CFBundleVersion|CFBundleShort|TermQBuildSHA"` — `CFBundleVersion` and `CFBundleShortVersionString` must be dot-notation (e.g. `0.7.0.b9`), NOT a git SHA; `TermQBuildSHA` must be the 7-char git SHA
2. **Appcast format:** `grep "sparkle:version" Docs/appcast-beta.xml | head -3` — must show dot-notation versions, NOT dash-notation
3. **Version detection:** Install the app, run another release — Sparkle must detect and offer the update (end-to-end test required after any version format change)
4. **Build artifact:** `codesign --verify --deep --strict --verbose=2 TermQ.app` passes
5. **ZIP archive:** Extract the ZIP, then run `codesign --verify --deep --strict` on the extracted app
6. **Framework symlinks:** `ls -la TermQ.app/Contents/Frameworks/Sparkle.framework/` shows symlinks (`l` prefix)
7. **EdDSA signature:** `.zip.sig` file exists, contains 88-char base64 string
8. **Appcast entries:** `sparkle:edSignature` attribute present and non-empty
9. **Download URL:** `curl -I -L <url>` returns 200 with correct content-length
10. **Signature verification:** `sign_update --verify <zip> <signature>` passes (requires private key)

## Known Pitfalls

| Pitfall | Consequence | Prevention |
|---|---|---|
| `CFBundleVersion` set to git SHA | SHA's leading hex digit compares as numerically huge; installed app is always "newer" than appcast — no update ever offered | Use `SPARKLE_VERSION` (dot-notation) for `CFBundleVersion` |
| Dash in `CFBundleVersion` or `sparkle:version` | `SUStandardVersionComparator` truncates at first dash; `0.7.0-beta.8` == `0.7.0-beta.9` — consecutive betas never update | Use dot-notation: `0.7.0.b9`, not `0.7.0-beta.9` |
| Using `zip -r` instead of `ditto` | Framework symlinks destroyed, codesign fails | Always use `ditto -c -k --keepParent` |
| Using `--deep` with codesign | XPC trust chain broken, install fails | Sign components individually, inside-out |
| curl without `-L` for GitHub assets | Gets empty body from 302 redirect | Always use `curl -sSL` |
| Missing `.zip.sig` release asset | Appcast has no signature, Sparkle rejects update | Verify asset list after release |
| Key pair mismatch | All signature verification fails | Never regenerate keys without updating Info.plist |
| Appcast served stale (GitHub Pages cache) | Users see old version | Wait 2-5 min after push, verify with `curl -I` |
| Pre-release in stable feed | Stable users see beta versions | `is_prerelease()` check in appcast generator |
| `echo` trailing newline in key pipe | Could corrupt key parsing | `sign_update` handles this; don't use `printf` without testing |

## Debugging

**Sparkle logs:** Enable Sparkle debug logging by adding `SUEnableAutomaticChecks` to UserDefaults and checking Console.app for `Sparkle` process output.

**Verify a release locally:**
```bash
# Download and extract
curl -sSL -o test.zip "https://github.com/eyelock/TermQ/releases/download/vX.Y.Z/TermQ-X.Y.Z.zip"
curl -sSL -o test.zip.sig "https://github.com/eyelock/TermQ/releases/download/vX.Y.Z/TermQ-X.Y.Z.zip.sig"

# Check signature format (should be 88 chars of base64)
cat test.zip.sig

# Extract and verify code signature
ditto -x -k test.zip /tmp/verify/
codesign --verify --deep --strict --verbose=2 /tmp/verify/TermQ.app

# Check framework structure
ls -la /tmp/verify/TermQ.app/Contents/Frameworks/Sparkle.framework/
# ALL top-level entries except Versions/ must be symlinks
```
