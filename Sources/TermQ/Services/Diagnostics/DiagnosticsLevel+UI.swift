import SwiftUI
import TermQCore

extension DiagnosticsLevel {
    var color: Color {
        switch self {
        case .debug: return .secondary
        case .info: return .blue
        case .notice: return .green
        case .warning: return .yellow
        case .error: return .red
        }
    }

    var filterLabel: String { label + "+" }
}
