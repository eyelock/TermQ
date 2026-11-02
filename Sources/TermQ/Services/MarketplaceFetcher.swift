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

    /// Clone the marketplace repo (or read a local folder) and parse its index.
    ///
    /// Returns an updated `Marketplace` with `plugins` populated and `lastFetched` set.
    /// Throws `FetchError` on any failure.
    static func fetch(marketplace: Marketplace) async throws -> Marketplace {
        if marketplace.isLocal {
            return try await fetchLocal(marketplace: marketplace)
        }
        return try await fetchRemote(marketplace: marketplace)
    }

    private static func fetchLocal(marketplace: Marketplace) async throws -> Marketplace {
        let folderURL = URL(fileURLWithPath: marketplace.localPath)
        return try parseIndex(in: folderURL, for: marketplace)
    }

    private static func fetchRemote(marketplace: Marketplace) async throws -> Marketplace {
        let gitPath = try findGit()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("termq-mkt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await clone(
            gitPath: gitPath, url: Marketplace.normalizeRepoURL(marketplace.url), ref: marketplace.ref,
            into: tempDir)
        return try parseIndex(in: tempDir, for: marketplace)
    }

    /// Locate and parse the vendor index under `repoRoot[/folder]`, mapping its plugins.
    /// Relative plugin sources resolve against the marketplace root (`repoRoot` + `folder`).
    static func parseIndex(in repoRoot: URL, for marketplace: Marketplace) throws -> Marketplace {
        var root = repoRoot
        if let folder = marketplace.normalizedFolder {
            root = repoRoot.appendingPathComponent(folder, isDirectory: true)
        }

        // Prefer the chosen vendor's layout, but fall back to any known vendor's so a marketplace
        // added under the wrong vendor (e.g. a Copilot repo added as Claude) still loads.
        let exists: (String) -> Bool = {
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
        }
        let candidates = marketplace.vendor.indexPaths + MarketplaceVendor.allCases.flatMap(\.indexPaths)
        guard let indexRelPath = candidates.first(where: exists) else {
            let shown = (marketplace.normalizedFolder.map { "\($0)/" } ?? "") + marketplace.vendor.indexPath
            throw FetchError.indexNotFound(shown)
        }
        let indexData: Data
        do { indexData = try Data(contentsOf: root.appendingPathComponent(indexRelPath)) } catch {
            throw FetchError.indexMalformed(error.localizedDescription)
        }
        let raw: RawMarketplaceIndex
        do {
            raw = try JSONDecoder().decode(RawMarketplaceIndex.self, from: indexData)
        } catch {
            throw FetchError.indexMalformed(error.localizedDescription)
        }

        var updated = marketplace
        if !marketplace.vendor.indexPaths.contains(indexRelPath),
            let detected = MarketplaceVendor.allCases.first(where: { $0.indexPaths.contains(indexRelPath) })
        {
            updated.vendor = detected
        }
        updated.name = raw.name ?? marketplace.name
        updated.owner = raw.owner ?? marketplace.owner
        if let desc = raw.description { updated.description = desc }
        updated.plugins = raw.plugins.map { mapPlugin($0, cloneRoot: root) }
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
        let cacheDir = pluginCacheURL(for: plugin.source.url, pin: plugin.source.pin)
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

        try await clone(gitPath: gitPath, url: cloneURL, ref: source.pin, into: cacheDir)

        // Stamp the version so future fetches can detect staleness
        try? (plugin.version ?? "").write(to: versionFile, atomically: true, encoding: .utf8)

        let root = source.path.map { cacheDir.appendingPathComponent($0) } ?? cacheDir
        return enumerateArtifacts(in: root)
    }

    // MARK: - Helpers

    private static func clone(gitPath: String, url: String, ref: String?, into dir: URL) async throws {
        // Detect SHA refs: 7-40 hex chars → can't use --branch, need post-clone checkout.
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        let isSHA =
            ref.map { r in
                r.count >= 7 && r.count <= 40 && r.unicodeScalars.allSatisfy { hex.contains($0) }
            } ?? false

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                // Build clone arguments.
                var cloneArgs = ["clone", "--quiet"]
                if let ref, !isSHA {
                    cloneArgs += ["--depth", "1", "--branch", ref]
                } else if ref == nil {
                    cloneArgs += ["--depth", "1"]
                }
                // SHA: omit --depth so we can checkout the specific commit afterward.
                cloneArgs += [url, dir.path]

                let cloneProcess = Process()
                let stderr = Pipe()
                cloneProcess.executableURL = URL(fileURLWithPath: gitPath)
                cloneProcess.arguments = cloneArgs
                cloneProcess.standardOutput = Pipe()
                cloneProcess.standardError = stderr

                do {
                    try cloneProcess.run()
                    cloneProcess.waitUntilExit()
                    guard cloneProcess.terminationStatus == 0 else {
                        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                        let errStr =
                            String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                            ?? ""
                        continuation.resume(throwing: FetchError.cloneFailed(errStr))
                        return
                    }
                } catch {
                    continuation.resume(throwing: FetchError.cloneFailed(error.localizedDescription))
                    return
                }

                // For SHA refs, checkout the specific commit after cloning.
                if let ref, isSHA {
                    let checkoutProcess = Process()
                    let checkoutErr = Pipe()
                    checkoutProcess.executableURL = URL(fileURLWithPath: gitPath)
                    checkoutProcess.arguments = ["-C", dir.path, "checkout", ref]
                    checkoutProcess.standardOutput = Pipe()
                    checkoutProcess.standardError = checkoutErr

                    do {
                        try checkoutProcess.run()
                        checkoutProcess.waitUntilExit()
                        if checkoutProcess.terminationStatus != 0 {
                            let errData = checkoutErr.fileHandleForReading.readDataToEndOfFile()
                            let errStr =
                                String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                                ?? ""
                            continuation.resume(throwing: FetchError.cloneFailed("checkout \(ref): \(errStr)"))
                            return
                        }
                    } catch {
                        continuation.resume(throwing: FetchError.cloneFailed(error.localizedDescription))
                        return
                    }
                }

                continuation.resume()
            }
        }
    }

    private static func mapPlugin(_ raw: RawMarketplacePlugin, cloneRoot: URL) -> MarketplacePlugin {
        var source = raw.source ?? PluginSourceSpec(type: .unknown, url: "")
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
            // A plugin folder may hold only a manifest that points at content elsewhere in the repo.
            // Follow it, and re-root the include at the marketplace root so the picks resolve.
            if picks.isEmpty {
                let redirected = redirectedArtifacts(pluginDir: root, marketplaceRoot: cloneRoot)
                if !redirected.isEmpty {
                    picks = redirected
                    source = PluginSourceSpec(type: .relative, url: "./")
                }
            }
            state = .eager
            if picks.isEmpty {
                let unsupported = unsupportedContentKinds(pluginDir: root)
                if !unsupported.isEmpty { state = .unsupported(unsupported.joined(separator: ", ")) }
            }
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

    /// Reads the `extensions."com.github.awesome-copilot"` block of a plugin's `plugin.json`, if any.
    private static func declaredContent(pluginDir: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: pluginDir.appendingPathComponent("plugin.json")),
            let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let extensions = manifest["extensions"] as? [String: Any]
        else { return nil }
        return extensions["com.github.awesome-copilot"] as? [String: Any]
    }

    /// Content types a plugin declares that cannot be picked (anything but skills/agents/commands/rules),
    /// e.g. `extensions` for a Copilot extension. Empty when the manifest declares none.
    static func unsupportedContentKinds(pluginDir: URL) -> [String] {
        let supported: Set<String> = ["skills", "agents", "commands", "rules"]
        guard let declared = declaredContent(pluginDir: pluginDir) else { return [] }
        return declared.compactMap { key, value in
            guard !supported.contains(key), let list = value as? [Any], !list.isEmpty else { return nil }
            return key
        }.sorted()
    }

    /// Artifacts a plugin declares in its `plugin.json` rather than holding itself.
    ///
    /// Copilot marketplaces (e.g. awesome-copilot) keep a thin `plugins/<name>/plugin.json` whose
    /// `extensions."com.github.awesome-copilot"` lists `skills`, `agents`, … as paths relative to the
    /// marketplace root. Agent entries are written `./agents/x.md` while the file is `x.agent.md`.
    /// Returns `type/name` picks relative to `marketplaceRoot`; Copilot "extensions" are not pickable.
    /// Only paths under the matching top-level folder (`skills/…`, `agents/…`) and inside the clone
    /// (no `..`, no symlinks leading out) are accepted, so every pick exists where `ynh` will look.
    static func redirectedArtifacts(pluginDir: URL, marketplaceRoot: URL) -> [String] {
        guard let declared = declaredContent(pluginDir: pluginDir) else { return [] }

        let fm = FileManager.default
        let rootPrefix = marketplaceRoot.resolvingSymlinksInPath().path + "/"

        /// Resolves a manifest path under `kind/` to a URL inside the clone, or nil.
        func resolve(_ raw: String, kind: String) -> (url: URL, rel: String)? {
            var rel = raw
            if rel.hasPrefix("./") { rel = String(rel.dropFirst(2)) }
            rel = rel.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let parts = rel.split(separator: "/")
            guard parts.count >= 2, parts[0] == kind, !parts.contains("..") else { return nil }
            let url = marketplaceRoot.appendingPathComponent(rel)
            guard url.resolvingSymlinksInPath().path.hasPrefix(rootPrefix) else { return nil }
            return (url, rel)
        }

        var results: [String] = []
        for raw in declared["skills"] as? [String] ?? [] {
            guard let item = resolve(raw, kind: "skills"),
                fm.fileExists(atPath: item.url.appendingPathComponent("SKILL.md").path)
            else { continue }
            results.append(item.rel)
        }
        for kind in ["agents", "commands", "rules"] {
            for raw in declared[kind] as? [String] ?? [] {
                guard let item = resolve(raw, kind: kind) else { continue }
                let stem = item.url.deletingPathExtension()
                let candidates = [item.url, stem.appendingPathExtension("agent.md"), stem.appendingPathExtension("md")]
                guard let found = candidates.first(where: { fm.fileExists(atPath: $0.path) }),
                    found.resolvingSymlinksInPath().path.hasPrefix(rootPrefix)
                else { continue }
                let dir = (item.rel as NSString).deletingLastPathComponent
                results.append("\(dir)/\(found.lastPathComponent)")
            }
        }
        return results.sorted()
    }

    /// Walk a plugin directory and collect all pickable artifacts with their type-prefixed paths.
    ///
    /// Returns paths in `type/name` format matching what `ynh include add --pick` expects:
    /// - `skills/<name>` — directory containing SKILL.md
    /// - `agents/<name>.md` — flat .md file
    /// - `commands/<name>.md` — flat .md file
    /// - `rules/<name>.md` — flat .md file
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
                    results.append("\(typeName)/\(entry.lastPathComponent)")
                }
            }
        }

        return results.sorted()
    }

    /// Cache directory for an external-source plugin, keyed by a stable FNV-1a hash of its source URL.
    /// Swift's `hashValue` is randomised per-process (hash-flood protection), so we use FNV-1a
    /// which produces the same result across launches for the same input.
    private static func pluginCacheURL(for sourceURL: String, pin: String?) -> URL {
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
            .appendingPathComponent(fnv1a64(pin.map { "\(sourceURL)@\($0)" } ?? sourceURL), isDirectory: true)
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
