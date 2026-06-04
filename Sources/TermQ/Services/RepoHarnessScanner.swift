import Foundation

/// A harness-shaped entry discovered in a repository working tree — any
/// directory containing `.ynh-plugin/plugin.json` (harnesses, plugins, and
/// skill collections all share this marker).
struct RepoHarnessEntry: Equatable, Sendable {
    /// The `name` field from the entry's manifest.
    let name: String
    /// Directory containing `.ynh-plugin/`, relative to the repo root.
    /// `"."` when the repo root itself is the harness (embedded layout).
    let relativePath: String
}

/// Result of scanning a target repository for existing harness entries.
struct RepoHarnessScan: Equatable, Sendable {
    let entries: [RepoHarnessEntry]
    /// Parent directories of discovered entries, most-populated first —
    /// destination *suggestions* inferred from where this repo already
    /// keeps harnesses. Never assumed; always user-editable.
    let suggestedParentDirs: [String]
    /// True when the repo provides an executable `scripts/ynh-register.sh`
    /// (the opt-in registration hook run after a publish copy).
    let hasRegisterScript: Bool

    /// The entry whose manifest name matches, if any — drives the
    /// new / update / clash decision in the publish sheet.
    func entry(named name: String) -> RepoHarnessEntry? {
        entries.first { $0.name == name }
    }
}

/// Scans a repository checkout for `*/.ynh-plugin/plugin.json` markers.
///
/// Read-only and defensive: unreadable directories and malformed manifests
/// are skipped, never thrown — a scan failure must not block the publish
/// sheet from opening (the user can still type a destination by hand).
enum RepoHarnessScanner {
    /// Conventional path of the repo-provided registration hook.
    static let registerScriptPath = "scripts/ynh-register.sh"

    /// Directory names never descended into.
    private static let skippedDirectories: Set<String> = [
        "node_modules", ".git", ".build", ".worktrees", "dist", "vendor",
    ]

    /// One directory pending a visit during the scan walk.
    private struct WalkEntry {
        let url: URL
        let relative: String
        let depth: Int
    }

    /// Scan `repoPath` for harness entries.
    ///
    /// - Parameter maxDepth: maximum number of path components for an
    ///   entry's directory relative to the repo root. The default of 3
    ///   covers every observed layout (root-embedded `.`, `ynh/<name>`,
    ///   `plugins/<name>`, and one level deeper for namespaced registries).
    static func scan(repoPath: String, maxDepth: Int = 3) -> RepoHarnessScan {
        var entries: [RepoHarnessEntry] = []
        let root = URL(fileURLWithPath: repoPath)

        // Depth-first walk, bounded by maxDepth and the skip list.
        var stack: [WalkEntry] = [WalkEntry(url: root, relative: ".", depth: 0)]
        while let entry = stack.popLast() {
            if let name = manifestName(inDirectory: entry.url) {
                entries.append(RepoHarnessEntry(name: name, relativePath: entry.relative))
                // Harness entries don't nest — no need to descend further.
                continue
            }
            guard entry.depth < maxDepth else { continue }
            let children =
                (try? FileManager.default.contentsOfDirectory(
                    at: entry.url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsPackageDescendants]
                )) ?? []
            for child in children {
                let childName = child.lastPathComponent
                guard !skippedDirectories.contains(childName), !childName.hasPrefix(".") else { continue }
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                    continue
                }
                let childRelative =
                    entry.relative == "." ? childName : "\(entry.relative)/\(childName)"
                stack.append(WalkEntry(url: child, relative: childRelative, depth: entry.depth + 1))
            }
        }

        entries.sort { $0.relativePath < $1.relativePath }

        // Rank parent dirs by how many entries they already hold.
        var parentCounts: [String: Int] = [:]
        for entry in entries where entry.relativePath != "." {
            let parent = (entry.relativePath as NSString).deletingLastPathComponent
            parentCounts[parent.isEmpty ? "." : parent, default: 0] += 1
        }
        let suggested = parentCounts.sorted {
            ($0.value, $1.key) > ($1.value, $0.key)
        }.map(\.key)

        let scriptURL = root.appendingPathComponent(registerScriptPath)
        let hasScript = FileManager.default.isExecutableFile(atPath: scriptURL.path)

        return RepoHarnessScan(
            entries: entries,
            suggestedParentDirs: suggested,
            hasRegisterScript: hasScript
        )
    }

    /// Decode the `name` from a directory's `.ynh-plugin/plugin.json`,
    /// or nil when the marker is absent or unreadable.
    private static func manifestName(inDirectory url: URL) -> String? {
        let manifestURL =
            url
            .appendingPathComponent(".ynh-plugin")
            .appendingPathComponent("plugin.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path),
            let data = try? Data(contentsOf: manifestURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let name = json["name"] as? String,
            !name.isEmpty
        else { return nil }
        return name
    }
}
