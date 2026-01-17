# Automatic Updates

TermQ includes built-in automatic update functionality powered by the [Sparkle](https://sparkle-project.org) framework. This ensures you always have the latest features and security fixes.

## How It Works

When updates are available:

1. TermQ periodically checks for new versions (once per day by default)
2. If an update is found, you'll see a notification dialog
3. Click **Install Update** to download and install automatically
4. TermQ will relaunch with the new version

The entire process is seamless - your terminal sessions are preserved across updates.

## Checking for Updates Manually

You can check for updates at any time:

- **Menu**: Go to **TermQ > Check for Updates...**
- **Settings**: Open Settings (⌘,) and click **Check for Updates** in the Updates section

## Update Settings

Configure update behavior in **Settings > Updates**:

| Setting | Description |
|---------|-------------|
| **Automatically check for updates** | When enabled, TermQ checks for updates once per day |
| **Include beta releases** | When enabled, you'll receive pre-release versions with new features |

## Release Channels

### Stable Channel (Default)

Stable releases are thoroughly tested and recommended for most users. These follow [semantic versioning](https://semver.org):

- **Major** (1.0.0 → 2.0.0): Significant changes, may include breaking changes
- **Minor** (1.0.0 → 1.1.0): New features, backward compatible
- **Patch** (1.0.0 → 1.0.1): Bug fixes and security updates

### Beta Channel

Enable **Include beta releases** in Settings to receive pre-release versions:

- Early access to new features
- Help test and provide feedback
- May contain bugs or incomplete features
- Version numbers include "-beta" suffix (e.g., 1.2.0-beta.1)

## Security

Updates are secure:

- **Code Signed**: All releases are signed with Apple Developer ID
- **Notarized**: Apps are notarized by Apple for additional verification
- **EdDSA Signed**: Update packages are cryptographically signed to prevent tampering
- **HTTPS Only**: Update checks and downloads use secure connections

## Troubleshooting

### Updates Not Working

1. **Check your internet connection** - Updates require network access
2. **Verify firewall settings** - Allow connections to `github.com` and `eyelock.github.io`
3. **Check manually** - Use **TermQ > Check for Updates...** to test

### Rolling Back

If you experience issues with a new version:

1. Download a previous version from [GitHub Releases](https://github.com/eyelock/TermQ/releases)
2. Quit TermQ
3. Replace the app in your Applications folder
4. Relaunch TermQ

### Disabling Automatic Updates

If needed, you can disable automatic updates:

1. Open **Settings** (⌘,)
2. In the **Updates** section, uncheck **Automatically check for updates**
3. You can still check manually via the menu

## Release Notes

Release notes are displayed in the update dialog when a new version is available. You can also view them on the [GitHub Releases](https://github.com/eyelock/TermQ/releases) page.

## Privacy

Update checks only send:
- Your current TermQ version
- macOS version
- System language

No personal data or terminal content is transmitted.
