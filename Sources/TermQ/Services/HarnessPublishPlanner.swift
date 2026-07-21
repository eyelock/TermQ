import Foundation
import TermQShared

/// A computed plan describing exactly which files a harness publish copies
/// into a repository worktree.
///
/// Built by ``HarnessPublishPlanner`` and rendered in the publish sheet as
/// the file-manifest preview before anything is copied.
struct HarnessPublishPlan: Equatable, Sendable {
    enum CopyMode: Equatable, Sendable {
        /// Copy every top-level entry of the source directory (minus junk).
        /// Default for self-contained sources — a directory that exists only
        /// to hold the harness.
        case entireDirectory
        /// Copy only the files the harness provably owns: the manifest dir,
        /// compose-attributed artifacts, and manifest-referenced scripts.
        /// Default for entangled sources whose root doubles as a project
        /// repo (detected via `.git` at the source root).
        case enumerated
    }

    let sourcePath: String
    let mode: CopyMode
    /// Relative copy roots (files or directories), sorted and deduped.
    /// Directory roots are copied recursively with junk filtering applied
    /// by the executor.
    let files: [String]
    /// References that could not be resolved into copyable paths: manifest
    /// artifacts/scripts missing on disk, and refs that escape the source
    /// root (`..`, absolute). Surfaced as drift warnings in the preview.
    let unresolvedReferences: [String]
}

enum HarnessPublishPlannerError: Error, Equatable {
    case sourceNotFound(String)
    case manifestNotFound(String)
    case manifestInvalid(String)
    /// Enumerated mode cannot be built without a successful `ynd compose` —
    /// artifact ownership is unknowable from the manifest alone, and
    /// guessing risks publishing host-project files.
    case compositionRequired
}

/// Pure planning logic for "Publish to Repository…".
///
/// Knows two things on purpose (agreed TermQ-side knowledge, with
/// `ynd validate` as the backstop for anything it gets wrong):
/// - the conventional artifact layout (`skills/<name>/`, `agents/<name>.md`,
///   `rules/<name>.md`, `commands/<name>.md`), probed against disk
/// - which manifest values are *content* references (hook / MCP / sensor
///   `command`s and `args`, when relative `./` paths) vs *runtime* reads
///   (sensor `source.files` — never copied)
enum HarnessPublishPlanner {
    /// Names never copied, in either mode, at any depth.
    static let junkNames: Set<String> = ["node_modules", ".git", ".DS_Store"]

    /// Entangled sources (root doubles as a git checkout — `.git` is a
    /// directory in a primary checkout, a file in linked worktrees) default
    /// to enumerated; self-contained directories default to entire-copy.
    static func defaultMode(forSourceAt sourcePath: String) -> HarnessPublishPlan.CopyMode {
        let gitPath = URL(fileURLWithPath: sourcePath).appendingPathComponent(".git").path
        return FileManager.default.fileExists(atPath: gitPath) ? .enumerated : .entireDirectory
    }

    /// Build the publish plan for a harness source directory.
    ///
    /// - Parameters:
    ///   - sourcePath: absolute path of the harness source (the directory
    ///     containing `.ynh-plugin/`).
    ///   - harnessName: the harness's own name — compose tags artifacts it
    ///     owns with this value in `ComposedArtifact.source`.
    ///   - composition: decoded `ynd compose` output. Required for
    ///     `.enumerated`; unused for `.entireDirectory`.
    ///   - mode: explicit override; defaults via ``defaultMode(forSourceAt:)``.
    static func plan(
        sourcePath: String,
        harnessName: String,
        composition: HarnessComposition?,
        mode: HarnessPublishPlan.CopyMode? = nil
    ) throws -> HarnessPublishPlan {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourcePath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw HarnessPublishPlannerError.sourceNotFound(sourcePath)
        }

        // A harness without a parseable manifest is not publishable in
        // either mode — validate would fail it anyway, so fail fast here.
        let manifest = try manifestJSON(at: sourcePath)

        let resolvedMode = mode ?? defaultMode(forSourceAt: sourcePath)
        switch resolvedMode {
        case .entireDirectory:
            return HarnessPublishPlan(
                sourcePath: sourcePath,
                mode: .entireDirectory,
                files: try topLevelRoots(at: sourcePath),
                unresolvedReferences: []
            )
        case .enumerated:
            guard let composition else {
                throw HarnessPublishPlannerError.compositionRequired
            }
            let (files, unresolved) = enumeratedRoots(
                sourcePath: sourcePath,
                harnessName: harnessName,
                composition: composition,
                manifest: manifest
            )
            return HarnessPublishPlan(
                sourcePath: sourcePath,
                mode: .enumerated,
                files: files,
                unresolvedReferences: unresolved
            )
        }
    }

    /// Post-copy honesty check: parse the manifest at `path` and return
    /// every `./`-relative reference that doesn't exist on disk there.
    ///
    /// `ynd validate` is schema-shape only — it does not probe referenced
    /// scripts (verified empirically) — so this is the check that catches
    /// "the hook script didn't make it across" after a publish copy.
    static func unresolvedManifestReferences(at path: String) throws -> [String] {
        let manifest = try manifestJSON(at: path)
        var refs: Set<String> = []
        collectScriptReferences(in: manifest, into: &refs)
        return resolveScriptReferences(refs, under: path).unresolved
    }

    // MARK: - Manifest

    private static func manifestJSON(at sourcePath: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: sourcePath)
            .appendingPathComponent(".ynh-plugin")
            .appendingPathComponent("plugin.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw HarnessPublishPlannerError.manifestNotFound(url.path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw HarnessPublishPlannerError.manifestInvalid(error.localizedDescription)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HarnessPublishPlannerError.manifestInvalid("Manifest is not a JSON object")
        }
        return json
    }

    // MARK: - Entire-directory mode

    private static func topLevelRoots(at sourcePath: String) throws -> [String] {
        let entries = try FileManager.default.contentsOfDirectory(atPath: sourcePath)
        return
            entries
            .filter { !junkNames.contains($0) }
            .sorted()
    }

    // MARK: - Enumerated mode

    /// One artifact category and the on-disk form its entries prefer.
    private struct ArtifactCategory {
        let directory: String
        let artifacts: [ComposedArtifact]
        let prefersDirectoryForm: Bool
    }

    private static func enumeratedRoots(
        sourcePath: String,
        harnessName: String,
        composition: HarnessComposition,
        manifest: [String: Any]
    ) -> (files: [String], unresolved: [String]) {
        var roots: Set<String> = [".ynh-plugin"]
        var unresolved: [String] = []

        // Compose-attributed artifacts, probed against the conventional
        // layout. Skills are directories; agents/rules/commands are
        // markdown files (directory form tolerated for forward compat).
        let categories = [
            ArtifactCategory(directory: "skills", artifacts: composition.artifacts.skills, prefersDirectoryForm: true),
            ArtifactCategory(directory: "agents", artifacts: composition.artifacts.agents, prefersDirectoryForm: false),
            ArtifactCategory(directory: "rules", artifacts: composition.artifacts.rules, prefersDirectoryForm: false),
            ArtifactCategory(
                directory: "commands", artifacts: composition.artifacts.commands, prefersDirectoryForm: false),
        ]
        for category in categories {
            for artifact in category.artifacts where artifact.source == harnessName {
                let directoryForm = "\(category.directory)/\(artifact.name)"
                let fileForm = "\(category.directory)/\(artifact.name).md"
                let candidates =
                    category.prefersDirectoryForm
                    ? [directoryForm, fileForm] : [fileForm, directoryForm]
                if let found = candidates.first(where: { exists($0, under: sourcePath) }) {
                    roots.insert(found)
                } else {
                    unresolved.append(directoryForm)
                }
            }
        }

        // Manifest-referenced scripts (hooks, profile hooks, MCP servers,
        // sensor commands). Runtime data reads (sensor `source.files`) are
        // structurally excluded — only `command` values and `args` elements
        // are ever considered, and only when they are `./`-relative.
        var scriptRefs: Set<String> = []
        collectScriptReferences(in: manifest, into: &scriptRefs)
        let resolved = resolveScriptReferences(scriptRefs, under: sourcePath)
        roots.formUnion(resolved.found)
        unresolved.append(contentsOf: resolved.unresolved)

        // Drop file roots already covered by a directory root so the
        // preview shows each copied path exactly once.
        let directoryRoots = roots.filter { isDirectory($0, under: sourcePath) }
        let covered = roots.filter { root in
            directoryRoots.contains { dir in
                dir != root && root.hasPrefix(dir + "/")
            }
        }
        roots.subtract(covered)

        return (roots.sorted(), unresolved.sorted())
    }

    /// Recursively collect candidate script references: every string under
    /// a `command` key and every string element of an `args` array. All
    /// other keys (including sensor `source.files`) are traversed but never
    /// collected.
    private static func collectScriptReferences(in value: Any, into refs: inout Set<String>) {
        if let dict = value as? [String: Any] {
            for (key, sub) in dict {
                switch key {
                case "command":
                    if let command = sub as? String {
                        refs.insert(command)
                    }
                case "args":
                    if let args = sub as? [Any] {
                        for element in args {
                            if let arg = element as? String {
                                refs.insert(arg)
                            }
                        }
                    }
                default:
                    collectScriptReferences(in: sub, into: &refs)
                }
            }
        } else if let array = value as? [Any] {
            for element in array {
                collectScriptReferences(in: element, into: &refs)
            }
        }
    }

    /// Resolve raw `command`/`args` values against a harness root.
    ///
    /// Only `./`-relative tokens are harness file references — everything
    /// else (PATH binaries, flags, plain args) is not ours to copy and not
    /// drift either. A `./` ref that escapes the root, or points at a
    /// missing file, lands in `unresolved`.
    private static func resolveScriptReferences(
        _ refs: Set<String>,
        under path: String
    ) -> (found: Set<String>, unresolved: [String]) {
        var found: Set<String> = []
        var unresolved: [String] = []
        for ref in refs.sorted() {
            guard let token = firstToken(of: ref), token.hasPrefix("./") else { continue }
            guard let normalized = normalizeReference(token) else {
                unresolved.append(ref)
                continue
            }
            if exists(normalized, under: path) {
                found.insert(normalized)
            } else {
                unresolved.append(normalized)
            }
        }
        return (found, unresolved)
    }

    /// A command may carry inline flags — the referenced file is the first
    /// whitespace-separated token.
    private static func firstToken(of raw: String) -> String? {
        raw.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }

    /// Resolve a `./`-prefixed token to a copyable relative path, or nil
    /// when the path would escape the source root.
    private static func normalizeReference(_ token: String) -> String? {
        let relative = String(token.dropFirst(2))
        let components = relative.split(separator: "/")
        guard !relative.isEmpty,
            !components.contains(".."),
            !relative.hasPrefix("/")
        else { return nil }
        return relative
    }

    // MARK: - Filesystem probes

    private static func exists(_ relative: String, under sourcePath: String) -> Bool {
        FileManager.default.fileExists(
            atPath: URL(fileURLWithPath: sourcePath).appendingPathComponent(relative).path)
    }

    private static func isDirectory(_ relative: String, under sourcePath: String) -> Bool {
        var isDirectory: ObjCBool = false
        let path = URL(fileURLWithPath: sourcePath).appendingPathComponent(relative).path
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
