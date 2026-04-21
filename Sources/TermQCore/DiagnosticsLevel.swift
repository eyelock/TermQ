import Foundation

public enum DiagnosticsLevel: String, CaseIterable, Comparable, Sendable {
    case debug, info, notice, warning, error

    public var label: String { rawValue.uppercased() }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        guard let lhsIdx = allCases.firstIndex(of: lhs),
            let rhsIdx = allCases.firstIndex(of: rhs)
        else { return false }
        return lhsIdx < rhsIdx
    }
}
