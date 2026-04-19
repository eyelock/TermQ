import Foundation

/// Fetches a vendor marketplace index by cloning the Git repo and parsing the JSON.
///
/// Strategy:
/// - Relative-path plugins: skill names enumerated immediately from the same clone (no extra
///   network traffic). `skillsState = .eager`.
/// - External-source plugins: marked `.pending`; cloned on demand and cached under
///   `~/Library/Application Support/TermQ/marketplace-cache/<plugin-id>/`.
enum MarketplaceFetcher {

    enum FetchError: Error, LocalizedError {
        case gitNotFound
        case cloneFailed(String)
        case indexNotFound(String)
        case indexMalformed(String)

        var errorDescription: String? {
            switch self {
            case .gitNotFound:
                return "git executable not found. Ensure git is installed."
            case .cloneFailed(let detail):
                return "Could not reach marketplace. Check the URL and your network. (\(detail))"
            case .indexNotFound(let path):
                return "Marketplace index not found at \(path)."
            case .indexMalformed(let detail):
                return "Marketplace index is malformed. \(detail)"
            }
        }
    }

    // MARK: - Public entry point

    /// Clone the marketplace repo and parse its index.
    ///
    /// Returns an updated `Marketplace` with `plugins` populated and `lastFetched` set.
    /// Throws `FetchError` on any failure.
    static func fetch(marketplace: Marketplace) async throws -> Marketplace {
        let gitPath = try findGit()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("termq-mkt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Clone
        try await clone(gitPath: gitPath, url: marketplace.url, into: tempDir)

        // Parse index
        let indexRelPath = marketplace.vendor.indexPath
        let indexURL = tempDir.appendingPathComponent(indexRelPath)
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            throw FetchError.indexNotFound(indexRelPath)
        }
        let indexData: Data
        do { indexData = try Data(contentsOf: indexURL) } catch {
            throw FetchError.indexMalformed(error.localizedDescription)
        }
        let raw: RawMarketplaceIndex
        do {
            raw = try JSONDecoder().decode(RawMarketplaceIndex.self, from: indexData)
        } catch {
            throw FetchError.indexMalformed(error.localizedDescription)
        }

        // Map plugins
        let plugins = raw.plugins.map { rawPlugin in
            mapPlugin(rawPlugin, cloneRoot: tempDir)
        }

        var updated = marketplace
        updated.name = raw.name ?? marketplace.name
        updated.owner = raw.owner ?? marketplace.owner
        if let desc = raw.description { updated.description = desc }
        updated.plugins = plugins
        updated.lastFetched = Date()
        updated.fetchError = nil
        return updated
    }

    // MARK: - Skill enumeration for external-source plugins (on-demand)

    /// Clone an external-source plugin and enumerate its skills.
    ///
    /// Results are cached under
    /// `~/Library/Application Support/TermQ/marketplace-cache/<url-hash>/`.
    /// The cache key is a stable hash of the source URL so it survives marketplace refreshes.
    /// A `version.txt` sentinel in the cache dir enables version-based invalidation: if
    /// `plugin.version` changes between refreshes the old clone is discarded and re-fetched.
    static func fetchSkills(for plugin: MarketplacePlugin) async throws -> [String] {
        let cacheDir = pluginCacheURL(for: plugin.source.url)
        let versionFile = cacheDir.appendingPathComponent(".termq-cache-version")

        // Validate existing cache: hit only if version file matches current plugin version
        if FileManager.default.fileExists(atPath: cacheDir.path) {
            let cachedVersion = (try? String(contentsOf: versionFile, encoding: .utf8)) ?? ""
            let currentVersion = plugin.version ?? ""
            if cachedVersion == currentVersion {
                let root = plugin.source.path.map { cacheDir.appendingPathComponent($0) } ?? cacheDir
                return enumerateArtifacts(in: root)
            }
            // Version mismatch — discard stale clone
            try? FileManager.default.removeItem(at: cacheDir)
        }

        let gitPath = try findGit()
        let source = plugin.source

        var cloneURL = source.url
        // For github type, construct https URL if it looks like "owner/repo"
        if source.type == .github, !cloneURL.hasPrefix("http") {
            cloneURL = "https://github.com/\(cloneURL)"
        }

        try await clone(gitPath: gitPath, url: cloneURL, into: cacheDir)

        // Stamp the version so future fetches can detect staleness
        try? (plugin.version ?? "").write(to: versionFile, atomically: true, encoding: .utf8)

        let root = source.path.map { cacheDir.appendingPathComponent($0) } ?? cacheDir
        return enumerateArtifacts(in: root)
    }

    // MARK: - Helpers

    private static func clone(gitPath: String, url: String, into dir: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stderr = Pipe()

                process.executableURL = URL(fileURLWithPath: gitPath)
                process.arguments = ["clone", "--depth", "1", "--quiet", url, dir.path]
                process.standardOutput = Pipe()
                process.standardError = stderr

                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                        let errStr =
                            String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                            ?? ""
                        continuation.resume(throwing: FetchError.cloneFailed(errStr))
                    }
                } catch {
                    continuation.resume(throwing: FetchError.cloneFailed(error.localizedDescription))
                }
            }
        }
    }

    private static func mapPlugin(_ raw: RawMarketplacePlugin, cloneRoot: URL) -> MarketplacePlugin {
        let source = raw.source ?? PluginSourceSpec(type: .unknown, url: "")
        let isRelative = source.type.isRelative

        var picks: [String] = []
        var state: SkillsLoadState = .pending

        if isRelative {
            let pluginDir = cloneRoot.appendingPathComponent(
                source.url.hasPrefix("./")
                    ? String(source.url.dropFirst(2))
                    : source.url)
            let root = source.path.map { pluginDir.appendingPathComponent($0) } ?? pluginDir
            picks = enumerateArtifacts(in: root)
            state = .eager
        }

        return MarketplacePlugin(
            id: UUID(),
            name: raw.name,
            description: raw.description,
            version: raw.version,
            category: raw.category,
            tags: raw.tags ?? [],
            source: source,
            picks: picks,
            skillsState: state
        )
    }

    /// Walk a plugin directory and collect all pickable artifacts with their type-prefixed paths.
    ///
    /// Returns paths in `type/name` format matching what `ynh include add --pick` expects:
    /// - `skills/<name>` — directory containing SKILL.md
    /// - `agents/<name>` — flat .md file
    /// - `commands/<name>` — flat .md file
    /// - `rules/<name>` — flat .md file
    static func enumerateArtifacts(in directory: URL) -> [String] {
        var results: [String] = []

        // Skills: subdirectories containing SKILL.md
        let skillsDir = directory.appendingPathComponent("skills")
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: skillsDir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) {
            for entry in entries {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDir),
                    isDir.boolValue,
                    FileManager.default.fileExists(atPath: entry.appendingPathComponent("SKILL.md").path)
                else { continue }
                results.append("skills/\(entry.lastPathComponent)")
            }
        }

        // Agents, commands, rules: flat .md files
        for typeName in ["agents", "commands", "rules"] {
            let typeDir = directory.appendingPathComponent(typeName)
            if let entries = try? FileManager.default.contentsOfDirectory(
                at: typeDir, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles
            ) {
                for entry in entries where entry.pathExtension == "md" {
                    results.append("\(typeName)/\(entry.deletingPathExtension().lastPathComponent)")
                }
            }
        }

        return results.sorted()
    }

    /// Cache directory for an external-source plugin, keyed by a stable FNV-1a hash of its source URL.
    /// Swift's `hashValue` is randomised per-process (hash-flood protection), so we use FNV-1a
    /// which produces the same result across launches for the same input.
    private static func pluginCacheURL(for sourceURL: String) -> URL {
        guard
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else {
            // Extremely unlikely fallback — applicationSupportDirectory is always available on macOS
            return URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/TermQ/marketplace-cache/fallback")
        }
        return
            appSupport
            .appendingPathComponent("TermQ/marketplace-cache", isDirectory: true)
            .appendingPathComponent(fnv1a64(sourceURL), isDirectory: true)
    }

    /// FNV-1a 64-bit hash — deterministic across processes, no external dependencies.
    private static func fnv1a64(_ str: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in str.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func findGit() throws -> String {
        let candidates = ["/usr/bin/git", "/usr/local/bin/git", "/opt/homebrew/bin/git"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Fallback: try `which git` synchronously (findGit is called from a background thread)
        let proc = Process()
        let out = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["git"]
        proc.standardOutput = out
        proc.standardError = Pipe()
        if (try? proc.run()) != nil {
            proc.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let trimmed = (String(data: data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        throw FetchError.gitNotFound
    }
}
