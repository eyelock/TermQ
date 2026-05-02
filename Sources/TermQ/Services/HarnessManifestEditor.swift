import Foundation
import TermQShared

/// Read/write helper for a harness's `.ynh-plugin/plugin.json` manifest.
///
/// Limited to the safe subset of fields that don't require ynh to validate
/// or fetch anything — `description`, `default_vendor`, `version`. Includes
/// and delegates are intentionally NOT touched here; those go through the
/// `ynh include`/`ynh delegate` commands.
///
/// Writes preserve every key the manifest already contains (`$schema`,
/// `name`, `includes`, etc.) by round-tripping through a JSON dictionary.
/// Order may be re-sorted alphabetically, which YNH tolerates.
enum HarnessManifestEditorError: Error, Equatable {
    case fileNotFound(String)
    case invalidJSON(String)
    case writeFailed(String)
}

struct HarnessManifestFields: Equatable {
    var description: String
    var defaultVendor: String
    var version: String
}

@MainActor
final class HarnessManifestEditor: ObservableObject {
    @Published private(set) var isWriting = false
    @Published var errorMessage: String?

    /// Read the editable manifest fields. Missing values come back as empty
    /// strings so the form binds cleanly.
    nonisolated static func read(at editablePath: String) throws -> HarnessManifestFields {
        let url = manifestURL(for: editablePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw HarnessManifestEditorError.fileNotFound(url.path)
        }
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HarnessManifestEditorError.invalidJSON("Manifest is not a JSON object")
        }
        return HarnessManifestFields(
            description: (json["description"] as? String) ?? "",
            defaultVendor: (json["default_vendor"] as? String) ?? "",
            version: (json["version"] as? String) ?? ""
        )
    }

    /// Write a subset of fields back to the manifest, preserving every other
    /// key. Empty string for `description` removes the key (manifests treat
    /// no description and empty description equivalently). Empty string for
    /// `defaultVendor` or `version` is rejected — those are required fields.
    nonisolated static func write(
        at editablePath: String,
        fields: HarnessManifestFields
    ) throws {
        let url = manifestURL(for: editablePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw HarnessManifestEditorError.fileNotFound(url.path)
        }
        let data = try Data(contentsOf: url)
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HarnessManifestEditorError.invalidJSON("Manifest is not a JSON object")
        }

        if fields.description.isEmpty {
            json.removeValue(forKey: "description")
        } else {
            json["description"] = fields.description
        }
        json["default_vendor"] = fields.defaultVendor
        json["version"] = fields.version

        let outData = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        do {
            try outData.write(to: url, options: .atomic)
        } catch {
            throw HarnessManifestEditorError.writeFailed(error.localizedDescription)
        }
    }

    /// Apply edits and trigger a detail re-fetch on success. Errors surface
    /// via `errorMessage` for the form to render.
    func apply(
        at editablePath: String,
        harnessName: String,
        fields: HarnessManifestFields,
        repository: HarnessRepository
    ) async -> Bool {
        errorMessage = nil
        isWriting = true
        defer { isWriting = false }
        do {
            try Self.write(at: editablePath, fields: fields)
            repository.invalidateDetail(for: harnessName)
            await repository.fetchDetail(for: harnessName)
            return true
        } catch let err as HarnessManifestEditorError {
            errorMessage = Self.message(for: err)
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    nonisolated private static func manifestURL(for editablePath: String) -> URL {
        URL(fileURLWithPath: editablePath)
            .appendingPathComponent(".ynh-plugin")
            .appendingPathComponent("plugin.json")
    }

    nonisolated private static func message(for error: HarnessManifestEditorError) -> String {
        switch error {
        case .fileNotFound(let path):
            return "Manifest not found at \(path)"
        case .invalidJSON(let detail):
            return "Manifest is malformed: \(detail)"
        case .writeFailed(let detail):
            return "Failed to write manifest: \(detail)"
        }
    }
}

// MARK: - Semver validation

/// Pure semver-shape check. Doesn't enforce monotonic increase — just that
/// the user's input has the expected MAJOR.MINOR.PATCH form (with optional
/// pre-release / build metadata suffixes).
enum SemverValidator {
    /// True when the candidate matches `MAJOR.MINOR.PATCH[-prerelease][+build]`.
    static func isValid(_ candidate: String) -> Bool {
        let pattern =
            #"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z\-\.]+)?(?:\+[0-9A-Za-z\-\.]+)?$"#
        return candidate.range(of: pattern, options: .regularExpression) != nil
    }
}
