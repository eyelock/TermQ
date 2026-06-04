import Foundation

/// A single file-level difference between a publish plan and the target
/// repo's existing copy of the harness.
struct PublishChange: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case added
        case modified
        case removed
    }

    /// Path relative to the harness root.
    let path: String
    let kind: Kind
}

/// Computes the added / modified / removed file list shown in the publish
/// sheet's update mode — the local-vs-published comparison surface.
///
/// Compares the plan's file set against a destination directory (the
/// registered repo's checkout in the form phase; the fresh worktree in the
/// progress phase). Size-then-bytes comparison; no git involved.
enum PublishChangePreview {

    /// Diff the plan against `destinationPath` (absolute path of the
    /// existing entry — repo checkout or worktree).
    ///
    /// Removed-file detection is scoped to the plan's *roots*: a file under
    /// a plan root that exists at the destination but not in the source is
    /// `removed`. Files outside every plan root (host-project files in
    /// root-embedded layouts) are never reported.
    static func diff(plan: HarnessPublishPlan, destinationPath: String) -> [PublishChange] {
        let sourceBase = URL(fileURLWithPath: plan.sourcePath)
        let destinationBase = URL(fileURLWithPath: destinationPath)
        var changes: [PublishChange] = []

        for root in plan.files {
            let sourceFiles = fileSet(under: sourceBase.appendingPathComponent(root), prefix: root)
            let destinationFiles = fileSet(
                under: destinationBase.appendingPathComponent(root), prefix: root)

            for path in sourceFiles.union(destinationFiles).sorted() {
                let inSource = sourceFiles.contains(path)
                let inDestination = destinationFiles.contains(path)
                switch (inSource, inDestination) {
                case (true, false):
                    changes.append(PublishChange(path: path, kind: .added))
                case (false, true):
                    changes.append(PublishChange(path: path, kind: .removed))
                case (true, true):
                    if !contentsEqual(
                        sourceBase.appendingPathComponent(path),
                        destinationBase.appendingPathComponent(path))
                    {
                        changes.append(PublishChange(path: path, kind: .modified))
                    }
                case (false, false):
                    break
                }
            }
        }

        return changes.sorted { $0.path < $1.path }
    }

    /// Relative paths of every regular file under `url` (or the single file
    /// itself when `url` is a file), junk-filtered. Empty when absent.
    private static func fileSet(under url: URL, prefix: String) -> Set<String> {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return [prefix] }

        var files: Set<String> = []
        var stack: [(url: URL, relative: String)] = [(url, prefix)]
        while let (current, relative) = stack.popLast() {
            let children = (try? fileManager.contentsOfDirectory(atPath: current.path)) ?? []
            for child in children {
                guard !HarnessPublishPlanner.junkNames.contains(child) else { continue }
                let childURL = current.appendingPathComponent(child)
                let childRelative = "\(relative)/\(child)"
                var childIsDirectory: ObjCBool = false
                fileManager.fileExists(atPath: childURL.path, isDirectory: &childIsDirectory)
                if childIsDirectory.boolValue {
                    stack.append((childURL, childRelative))
                } else {
                    files.insert(childRelative)
                }
            }
        }
        return files
    }

    private static func contentsEqual(_ lhs: URL, _ rhs: URL) -> Bool {
        FileManager.default.contentsEqual(atPath: lhs.path, andPath: rhs.path)
    }
}
