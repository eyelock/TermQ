import Foundation

/// Minimal abstraction over the subset of `UserDefaults` that TermQ uses for
/// preference storage. Existing call sites can default to `UserDefaults.standard`;
/// tests inject `InMemoryKeyValueStore` to keep preferences out of the user's
/// real defaults database.
public protocol KeyValueStore: AnyObject {
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool
    func integer(forKey key: String) -> Int
    func double(forKey key: String) -> Double
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func set(_ value: Bool, forKey key: String)
    func set(_ value: Int, forKey key: String)
    func set(_ value: Double, forKey key: String)
}

extension UserDefaults: KeyValueStore {}
