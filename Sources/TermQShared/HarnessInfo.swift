import Foundation

/// Thin identity + provenance response decoded from `ynh info <name> --format json`.
///
/// This is the first half of the detail pane data. The second half comes from
/// `ynd compose` (see ``HarnessComposition``). TermQ merges both into a single
/// ``HarnessDetail`` view model.
public struct HarnessInfo: Codable, Sendable {
    public let name: String
    /// The currently installed version. Maps from YNH's `version_installed` key.
    public let version: String
    public let description: String?
    public let defaultVendor: String
    public let path: String
    public let installedFrom: HarnessProvenance?
    /// True when the harness is structurally pinned to a specific commit SHA.
    /// Absent on YNH builds older than 0.3.0 — treat nil as `false`.
    public let isPinned: Bool?

    /// The raw `plugin.json` manifest. TermQ does not interpret this — it is
    /// passed through for diagnostic display only (e.g. a "View manifest" disclosure).
    /// Stored as an opaque JSON string to avoid modelling YNH's internal schema.
    public let manifest: JSONFragment?

    enum CodingKeys: String, CodingKey {
        case name, description, path, manifest
        case version = "version_installed"
        case defaultVendor = "default_vendor"
        case installedFrom = "installed_from"
        case isPinned = "is_pinned"
    }
}

/// An opaque JSON value stored as its raw string representation.
///
/// Used to carry the manifest field from `ynh info` without interpreting it.
/// Decodes any valid JSON value and re-encodes it as pretty-printed text.
public struct JSONFragment: Codable, Sendable, Equatable {
    public let rawString: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Decode the raw JSON bytes so we can re-encode them pretty-printed.
        let rawValue = try container.decode(RawJSON.self)
        let data = try JSONSerialization.data(
            withJSONObject: rawValue.value,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        rawString = String(data: data, encoding: .utf8) ?? "{}"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        // Write it back as a raw JSON fragment.
        guard let data = rawString.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data)
        else {
            try container.encodeNil()
            return
        }
        try container.encode(RawJSON(value: obj))
    }
}

/// Internal helper for round-tripping arbitrary JSON through Codable.
private struct RawJSON: Codable {
    let value: Any

    init(value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: RawJSON].self) {
            value = dict.mapValues(\.value)
        } else if let array = try? container.decode([RawJSON].self) {
            value = array.map(\.value)
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let number = try? container.decode(Double.self) {
            value = number
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { RawJSON(value: $0) })
        case let array as [Any]:
            try container.encode(array.map { RawJSON(value: $0) })
        case let string as String:
            try container.encode(string)
        case let number as Double:
            try container.encode(number)
        case let bool as Bool:
            try container.encode(bool)
        case is NSNull:
            try container.encodeNil()
        default:
            try container.encodeNil()
        }
    }
}
