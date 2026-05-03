import Foundation

/// Generic four-state model for an asynchronously-loaded resource.
///
/// Distinguishes "never loaded" (`.idle`) from "loading right now" (`.loading`)
/// from "loaded with a value" (`.loaded`) from "load failed" (`.error`). This
/// is the readiness primitive that lets consumers (sheets, lists, detail views)
/// gate UI on actually-loaded data instead of papering over the empty-vs-loading
/// ambiguity that produced the launch-pill bug.
enum LoadState<Value: Equatable>: Equatable {
    case idle
    case loading
    case loaded(Value)
    case error(String)

    /// The contained value when in `.loaded`, otherwise `nil`.
    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    /// True when in `.loaded` — the consumer can rely on `value`.
    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    /// True when in `.loading` — a refresh is in flight.
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
