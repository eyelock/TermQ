import SwiftUI

/// Status state for StatusIndicator
enum StatusIndicatorState {
    case active
    case ready
    case installed
    case disabled
    case inactive
    case error

    var color: Color {
        switch self {
        case .active, .ready, .installed:
            return .green
        case .disabled, .inactive:
            return .secondary
        case .error:
            return .red
        }
    }

    var icon: String {
        switch self {
        case .active, .ready, .installed:
            return "checkmark.circle.fill"
        case .disabled, .inactive:
            return "circle.fill"
        case .error:
            return "exclamationmark.circle.fill"
        }
    }
}

/// Reusable status line showing feature/service state
///
/// Features:
/// - Icon + descriptive text + status indicator
/// - Consistent styling across all uses
/// - Color-coded states (green for active/ready, gray for disabled/inactive)
///
/// Usage:
/// ```swift
/// StatusIndicator(
///     icon: "cpu",
///     label: "MCP Server",
///     status: .installed,
///     message: "Installed"
/// )
/// ```
///
/// Example outputs:
/// - 🟢 MCP Server: Installed
/// - ⚫ Feature disabled globally
/// - 🔴 Configuration error
struct StatusIndicator: View {
    let icon: String
    let label: String
    let status: StatusIndicatorState
    let message: String

    init(
        icon: String,
        label: String,
        status: StatusIndicatorState,
        message: String
    ) {
        self.icon = icon
        self.label = label
        self.status = status
        self.message = message
    }

    var body: some View {
        HStack(spacing: 6) {
            // Leading icon
            Image(systemName: icon)
                .foregroundColor(status.color)
                .imageScale(.medium)

            // Label + message
            Text("\(label):")
                .foregroundColor(.primary)
                + Text(" \(message)")
                .foregroundColor(.secondary)

            Spacer()

            // Status indicator (colored dot)
            Image(systemName: status.icon)
                .foregroundColor(status.color)
                .imageScale(.small)
        }
        .font(.caption)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
