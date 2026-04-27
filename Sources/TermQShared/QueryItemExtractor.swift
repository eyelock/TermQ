import Foundation

/// Extracts typed values from a URL query item list.
/// Eliminates repeated `queryItems.first { $0.name == "key" }?.value` call sites.
public struct QueryItemExtractor: Sendable {
    public let items: [URLQueryItem]

    public init(_ items: [URLQueryItem]) {
        self.items = items
    }

    public init(_ components: URLComponents) {
        self.items = components.queryItems ?? []
    }

    /// Returns the first value for `name`, or `fallback` if absent.
    public func string(_ name: String, default fallback: String = "") -> String {
        items.first { $0.name == name }?.value ?? fallback
    }

    /// Returns the first value for `name`, or nil if absent.
    public func optionalString(_ name: String) -> String? {
        items.first { $0.name == name }?.value
    }

    /// Returns the first value for `name` parsed as a UUID, or nil.
    public func uuid(_ name: String) -> UUID? {
        guard let value = items.first(where: { $0.name == name })?.value else { return nil }
        return UUID(uuidString: value)
    }

    /// Returns the first value for `name` parsed as a Bool, or `fallback`.
    /// Accepts "true"/"false", "1"/"0", "yes"/"no" (case-insensitive).
    public func bool(_ name: String, default fallback: Bool = false) -> Bool {
        guard let value = items.first(where: { $0.name == name })?.value else { return fallback }
        switch value.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return fallback
        }
    }

    /// Returns the first value for `name` parsed as a Bool, or nil if absent.
    public func optionalBool(_ name: String) -> Bool? {
        guard let value = items.first(where: { $0.name == name })?.value else { return nil }
        switch value.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return nil
        }
    }

    /// Returns the first value for `name` parsed as an Int, or `fallback`.
    public func int(_ name: String, default fallback: Int = 0) -> Int {
        guard let value = items.first(where: { $0.name == name })?.value else { return fallback }
        return Int(value) ?? fallback
    }

    /// Returns all values for `name`, trimmed of whitespace, with empty strings removed.
    /// Useful for repeated query parameters (e.g. multiple `tag=...` items).
    public func allValues(_ name: String) -> [String] {
        items
            .filter { $0.name == name }
            .compactMap { $0.value }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
