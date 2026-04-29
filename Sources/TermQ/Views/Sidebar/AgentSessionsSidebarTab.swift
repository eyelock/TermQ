import SwiftUI

/// Sidebar content for the Agent Sessions tab.
///
/// Placeholder for the v1 agent loop capability — see
/// `.claude/plans/2026-04-29-feat-agent-loop.md`. Wiring to live agent-card
/// data lands in a later slice.
struct AgentSessionsSidebarTab: View {
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            emptyState
        }
    }

    private var header: some View {
        HStack {
            Text("Agent Sessions")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No agent sessions yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Start one from a harness to drive a loop of edits → sensors → feedback.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
