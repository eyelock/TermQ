import Foundation

/// Optional focus-source override within a sensor overlay.
public struct SensorOverlayFocus: Codable, Sendable, Equatable {
    public var prompt: String
    public var profile: String?

    public init(prompt: String, profile: String? = nil) {
        self.prompt = prompt
        self.profile = profile
    }
}

/// Optional source override within a sensor overlay.
public struct SensorOverlaySource: Codable, Sendable, Equatable {
    public var focus: SensorOverlayFocus?

    public init(focus: SensorOverlayFocus? = nil) {
        self.focus = focus
    }

    public var isEmpty: Bool { focus == nil }
}

/// Session-local overlay for a single sensor declaration.
///
/// Only declared fields are applied by the loop driver; unset fields inherit
/// the harness's declaration. Wire format matches the `--sensor-overlay` JSON
/// accepted by the `ynh-agent` loop driver.
public struct SensorOverlay: Codable, Sendable, Equatable {
    public var role: String?
    public var source: SensorOverlaySource?

    public init(role: String? = nil, source: SensorOverlaySource? = nil) {
        self.role = role
        self.source = source
    }

    public var isEmpty: Bool {
        role == nil && (source?.isEmpty ?? true)
    }
}

/// Session-local overlays keyed by sensor name.
/// Serialised as JSON to `<session-dir>/sensor-overlays.json`.
public typealias SensorOverlays = [String: SensorOverlay]
