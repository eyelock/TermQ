import SwiftUI

/// A dismissible banner shown at the bottom of the sidebar after PR checkout.
///
/// Persists until explicitly dismissed — no auto-dismiss timer —  because it may
/// carry an action button (plan decision: toasts with actions don't auto-dismiss).
struct SidebarToastBanner: View {
    let toast: SidebarToast
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(toast.message)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(2)

            Spacer()

            if let label = toast.actionLabel, let action = toast.action {
                Button(label) {
                    action()
                    onDismiss()
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .foregroundColor(.white.opacity(0.85))
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .imageScale(.small)
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.78))
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
