import Foundation
import TermQCore

/// Persists session-local sensor overlays to `sensor-overlays.json`.
///
/// Path: `<appSupport>/TermQ[-Debug]/agent-sessions/<sessionId>/sensor-overlays.json`
///
/// The JSON format matches the `--sensor-overlay` payload accepted by the
/// `ynh-agent` loop driver — the file can be read and forwarded directly at
/// session launch time.
enum SensorOverlayStore {
    static func load(for sessionId: UUID, baseDirectory: URL? = nil) -> SensorOverlays {
        let url = fileURL(for: sessionId, baseDirectory: baseDirectory)
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode(SensorOverlays.self, from: data)) ?? [:]
    }

    static func save(_ overlays: SensorOverlays, for sessionId: UUID, baseDirectory: URL? = nil) {
        let url = fileURL(for: sessionId, baseDirectory: baseDirectory)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(overlays) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func fileURL(for sessionId: UUID, baseDirectory: URL? = nil) -> URL {
        let base = baseDirectory ?? TrajectoryWriter.defaultAgentSessionsDirectory()
        return base
            .appendingPathComponent(sessionId.uuidString, isDirectory: true)
            .appendingPathComponent("sensor-overlays.json")
    }

    /// Serialises non-empty overlays to a compact JSON string suitable for
    /// passing as `--sensor-overlay <json>` to the loop driver.
    static func serialise(_ overlays: SensorOverlays) -> String? {
        let nonEmpty = overlays.filter { !$0.value.isEmpty }
        guard !nonEmpty.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(nonEmpty) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
