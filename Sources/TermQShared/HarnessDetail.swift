/// TermQ-side merge of `ynh info` + `ynd compose`.
///
/// This type lives only in TermQ — YNH never emits this shape. The detail
/// pane reads from here. Created by ``HarnessRepository`` after fetching
/// both halves.
public struct HarnessDetail: Sendable {
    /// Identity and provenance from `ynh info <name> --format json`.
    public let info: HarnessInfo

    /// Composed vendor-neutral view from `ynd compose <info.path>`.
    public let composition: HarnessComposition

    public init(info: HarnessInfo, composition: HarnessComposition) {
        self.info = info
        self.composition = composition
    }
}
