import Foundation

/// Widths of the panes on the Wheelhouse stage.
///
/// Each pane has a weight; its width is its share of the space. Dragging the
/// divider between two panes moves weight from one to the other, never below
/// a minimum width, so the panes outside the pair keep their size.
public enum WheelhousePaneSizing {
    public static let defaultWeight: CGFloat = 1

    /// The width of each pane, in order, sharing `available` by weight.
    public static func widths(weights: [CGFloat], available: CGFloat) -> [CGFloat] {
        let total = weights.reduce(0, +)
        guard total > 0, available > 0 else {
            return weights.map { _ in weights.isEmpty ? 0 : max(0, available) / CGFloat(weights.count) }
        }
        return weights.map { available * $0 / total }
    }

    /// Weight per point of width, for converting a drag to weight at the
    /// same scale as `widths`: the total weight over every pane, over the space.
    public static func weightPerPoint(weights: [CGFloat], available: CGFloat) -> CGFloat {
        available > 0 ? weights.reduce(0, +) / available : 0
    }

    /// The pair's weights after dragging the divider between them `delta`
    /// points to the right.
    public static func resized(
        left: CGFloat, right: CGFloat, weightPerPoint perPoint: CGFloat, delta: CGFloat, minWidth: CGFloat
    ) -> (left: CGFloat, right: CGFloat) {
        guard perPoint > 0 else { return (left, right) }
        let pair = left + right
        // Neither side narrower than minWidth, unless the pair can't fit two.
        let minWeight = min(minWidth * perPoint, pair / 2)
        let newLeft = min(max(left + delta * perPoint, minWeight), pair - minWeight)
        return (newLeft, pair - newLeft)
    }
}
