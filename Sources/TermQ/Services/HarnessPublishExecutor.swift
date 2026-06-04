import Foundation

/// Outcome of a publish copy — rendered step-by-step in the progress sheet.
struct HarnessPublishReport: Equatable, Sendable {
    /// Relative roots copied into the destination.
    let copiedRoots: [String]
    /// Relative paths deleted from the destination (update-mode sync).
    let deletedPaths: [String]
    /// Non-fatal conditions the user should see (e.g. deletions skipped
    /// because the destination's own file set couldn't be enumerated).
    let warnings: [String]
}

enum HarnessPublishExecutorError: Error, Equatable {
    /// Destination contains something that isn't this harness — publishing
    /// would clobber unrelated files. Blocked upstream by the sheet; this
    /// is the executor's own guard.
    case destinationOccupied(String)
    /// The destination path escapes the worktree (`..` or absolute).
    case invalidDestination(String)
    case copyFailed(String)
    case manifestRewriteFailed(String)
}

/// File operations for "Publish to Repository…". No UI, no subprocesses —
/// everything here is deterministic FileManager work, unit-tested with
/// temp-dir fixtures.
///
/// Deletion safety model (the part that earns the tests):
/// - *Dedicated harness dir* (non-root destination containing `.ynh-plugin/`):
///   update-mode may wholesale-replace the directory.
/// - *Root or shared destination*: never wholesale-deleted. Each plan root
///   is replaced individually; stale roots are deleted only when the
///   caller provides the destination's own file set (`existingFileRoots`),
///   and never when that enumeration failed.
enum HarnessPublishExecutor {

    // MARK: - Copy

    /// Copy a publish plan into a worktree.
    ///
    /// - Parameters:
    ///   - plan: what to copy, from ``HarnessPublishPlanner``.
    ///   - worktreePath: absolute path of the freshly created worktree.
    ///   - destinationRelativePath: harness directory relative to the
    ///     worktree root; `"."` publishes into the root itself.
    ///   - renameTo: when non-nil, the copied manifest's `name` field is
    ///     rewritten (mirrors `ynh fork --name` identity coherence).
    ///   - isUpdate: true when overwriting an existing entry the user
    ///     explicitly confirmed updating.
    ///   - existingFileRoots: the destination entry's own relative roots
    ///     (planner output against the destination) used to propagate
    ///     deletions in root/shared destinations. Pass nil when unknown —
    ///     deletions are skipped and a warning is emitted instead.
    static func execute(
        plan: HarnessPublishPlan,
        worktreePath: String,
        destinationRelativePath: String,
        renameTo: String? = nil,
        isUpdate: Bool,
        existingFileRoots: [String]? = nil
    ) throws -> HarnessPublishReport {
        let worktreeURL = URL(fileURLWithPath: worktreePath).standardizedFileURL
        let destinationURL = try resolveDestination(
            relative: destinationRelativePath, under: worktreeURL)
        let isRootDestination = destinationURL.path == worktreeURL.path
        let fileManager = FileManager.default

        var deletedPaths: [String] = []
        var warnings: [String] = []

        if isUpdate {
            // Wholesale replacement is only ever safe for a directory that
            // exists purely to hold this harness.
            if !isRootDestination, isDedicatedHarnessDir(destinationURL) {
                do {
                    try fileManager.removeItem(at: destinationURL)
                } catch {
                    throw HarnessPublishExecutorError.copyFailed(
                        "removing existing entry \(destinationRelativePath): \(error.localizedDescription)")
                }
                deletedPaths.append(destinationRelativePath)
            } else {
                // Root/shared destination: per-root sync. Delete stale
                // roots only with a trustworthy enumeration of what the
                // existing entry owns.
                if let existing = existingFileRoots {
                    let stale = Set(existing).subtracting(plan.files)
                    for root in stale.sorted() {
                        let target = destinationURL.appendingPathComponent(root)
                        guard target.standardizedFileURL.path.hasPrefix(worktreeURL.path + "/") else {
                            continue
                        }
                        if fileManager.fileExists(atPath: target.path) {
                            try? fileManager.removeItem(at: target)
                            deletedPaths.append(root)
                        }
                    }
                } else {
                    warnings.append(
                        "Existing entry's file set could not be enumerated — stale files were not deleted."
                    )
                }
            }
        } else {
            // New entry: the destination must not already hold a harness.
            if fileManager.fileExists(
                atPath: destinationURL.appendingPathComponent(".ynh-plugin").path)
            {
                throw HarnessPublishExecutorError.destinationOccupied(destinationRelativePath)
            }
        }

        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        var copiedRoots: [String] = []
        for root in plan.files {
            let source = URL(fileURLWithPath: plan.sourcePath).appendingPathComponent(root)
            let target = destinationURL.appendingPathComponent(root)
            guard fileManager.fileExists(atPath: source.path) else {
                warnings.append("Planned file disappeared before copy: \(root)")
                continue
            }
            do {
                // Replace-per-root so deletions *inside* a copied directory
                // propagate on update.
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }
                try copyFiltered(from: source, to: target)
                copiedRoots.append(root)
            } catch {
                throw HarnessPublishExecutorError.copyFailed(
                    "\(root): \(error.localizedDescription)")
            }
        }

        // Install provenance never ships — same rule as `ynh fork`.
        let installedJSON =
            destinationURL
            .appendingPathComponent(".ynh-plugin")
            .appendingPathComponent("installed.json")
        if fileManager.fileExists(atPath: installedJSON.path) {
            try? fileManager.removeItem(at: installedJSON)
        }

        if let renameTo, !renameTo.isEmpty {
            try rewriteManifestName(at: destinationURL, to: renameTo)
        }

        return HarnessPublishReport(
            copiedRoots: copiedRoots,
            deletedPaths: deletedPaths,
            warnings: warnings
        )
    }

    // MARK: - Destination rules

    /// True when the directory exists purely to hold a harness — it has a
    /// `.ynh-plugin/` marker, making wholesale replacement safe.
    static func isDedicatedHarnessDir(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let marker = url.appendingPathComponent(".ynh-plugin").path
        return FileManager.default.fileExists(atPath: marker, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func resolveDestination(relative: String, under worktreeURL: URL) throws -> URL {
        guard !relative.hasPrefix("/") else {
            throw HarnessPublishExecutorError.invalidDestination(relative)
        }
        let resolved = worktreeURL.appendingPathComponent(relative).standardizedFileURL
        guard resolved.path == worktreeURL.path || resolved.path.hasPrefix(worktreeURL.path + "/")
        else {
            throw HarnessPublishExecutorError.invalidDestination(relative)
        }
        return resolved
    }

    // MARK: - Filtered copy

    /// Recursive copy that skips junk names at every depth.
    private static func copyFiltered(from source: URL, to target: URL) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory)

        guard isDirectory.boolValue else {
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: target)
            return
        }

        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        for child in try fileManager.contentsOfDirectory(atPath: source.path) {
            guard !HarnessPublishPlanner.junkNames.contains(child) else { continue }
            try copyFiltered(
                from: source.appendingPathComponent(child),
                to: target.appendingPathComponent(child)
            )
        }
    }

    // MARK: - Manifest rename

    /// Rewrite the destination manifest's `name`, preserving every other
    /// key (round-trip through a JSON dictionary, same approach as
    /// `HarnessManifestEditor`).
    private static func rewriteManifestName(at destinationURL: URL, to newName: String) throws {
        let manifestURL =
            destinationURL
            .appendingPathComponent(".ynh-plugin")
            .appendingPathComponent("plugin.json")
        do {
            let data = try Data(contentsOf: manifestURL)
            guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HarnessPublishExecutorError.manifestRewriteFailed(
                    "Manifest is not a JSON object")
            }
            json["name"] = newName
            let outData = try JSONSerialization.data(
                withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try outData.write(to: manifestURL, options: .atomic)
        } catch let error as HarnessPublishExecutorError {
            throw error
        } catch {
            throw HarnessPublishExecutorError.manifestRewriteFailed(error.localizedDescription)
        }
    }
}

// MARK: - ynd validate wrapper

/// Result of `ynd validate` against a harness directory.
///
/// Characterized empirically (2026-06-04): success prints `<path>: valid`
/// and exits 0; failure prints `<path>: INVALID` plus `  - <reason>` bullet
/// lines on stdout, `Error: validation failed` on stderr, and exits 1.
/// Validation is schema-shape only — it does not resolve includes and does
/// not probe referenced scripts (that's
/// ``HarnessPublishPlanner/unresolvedManifestReferences(at:)``'s job).
struct YndValidationResult: Equatable, Sendable {
    let isValid: Bool
    /// Human-readable findings parsed from the `  - ` bullets.
    let findings: [String]
    let rawOutput: String
}

/// Async wrapper around `ynd validate`, injectable via `YNHCommandRunner`
/// for tests.
struct YndValidateRunner: Sendable {
    let commandRunner: any YNHCommandRunner

    init(commandRunner: any YNHCommandRunner = LiveYNHCommandRunner()) {
        self.commandRunner = commandRunner
    }

    /// Run `ynd validate` with the harness directory as the working
    /// directory (the CLI validates its cwd).
    func validate(
        yndPath: String,
        harnessPath: String,
        environment: [String: String]? = nil
    ) async throws -> YndValidationResult {
        let result = try await commandRunner.run(
            executable: yndPath,
            arguments: ["validate"],
            environment: environment,
            currentDirectory: harnessPath,
            onStdoutLine: nil,
            onStderrLine: nil
        )
        let findings = result.stdout
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") }
            .map { String($0.dropFirst(2)) }
        return YndValidationResult(
            isValid: result.didSucceed,
            findings: findings,
            rawOutput: result.stdout
        )
    }
}
