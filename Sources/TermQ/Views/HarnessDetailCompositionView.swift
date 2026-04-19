import SwiftUI
import TermQShared

/// Composition sections for the harness detail pane: hooks, MCP servers,
/// profiles, and focuses.
struct HarnessDetailCompositionView: View {
    let composition: HarnessComposition

    var body: some View {
        Group {
            Divider()
            hooksSection(composition.hooks)

            Divider()
            mcpSection(composition.mcpServers)

            Divider()
            profilesSection(composition.profiles)

            Divider()
            focusesSection(composition.focuses)
        }
    }

    // MARK: - Hooks

    private func hooksSection(_ hooks: [String: [ComposedHook]]?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Harnesses.detailHooks)
                .font(.headline)

            if let hooks, !hooks.isEmpty {
                ForEach(hooks.keys.sorted(), id: \.self) { event in
                    if let entries = hooks[event] {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.orange)

                            ForEach(Array(entries.enumerated()), id: \.offset) { _, hook in
                                HStack(spacing: 6) {
                                    Text(hook.command)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)

                                    if let matcher = hook.matcher, !matcher.isEmpty {
                                        Text("(\(matcher))")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.leading, 12)
                            }
                        }
                    }
                }
            } else {
                emptyHint(Strings.Harnesses.detailNoHooks)
            }
        }
    }

    // MARK: - MCP Servers

    private func mcpSection(_ servers: [String: ComposedMCPServer]?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Harnesses.detailMCPServers)
                .font(.headline)

            if let servers, !servers.isEmpty {
                ForEach(servers.keys.sorted(), id: \.self) { name in
                    if let server = servers[name] {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name)
                                .font(.system(size: 12, weight: .medium))

                            if let command = server.command, !command.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "terminal")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Text(command)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                    if let args = server.args, !args.isEmpty {
                                        Text(args.joined(separator: " "))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .textSelection(.enabled)
                                    }
                                }
                                .padding(.leading, 12)
                            }

                            if let url = server.url, !url.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Text(url)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                .padding(.leading, 12)
                            }
                        }
                    }
                }
            } else {
                emptyHint(Strings.Harnesses.detailNoMCPServers)
            }
        }
    }

    // MARK: - Profiles

    private func profilesSection(_ profiles: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Harnesses.detailProfiles)
                .font(.headline)

            if !profiles.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(profiles, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            } else {
                emptyHint(Strings.Harnesses.detailNoProfiles)
            }
        }
    }

    // MARK: - Focuses

    private func focusesSection(_ focuses: [String: ComposedFocus]?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Harnesses.detailFocuses)
                .font(.headline)

            if let focuses, !focuses.isEmpty {
                ForEach(focuses.keys.sorted(), id: \.self) { name in
                    if let focus = focuses[name] {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(name)
                                    .font(.system(size: 12, weight: .medium))

                                if let profile = focus.profile, !profile.isEmpty {
                                    Text(Strings.Harnesses.detailFocusProfile(profile))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }

                            Text(focus.prompt)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.leading, 12)
                                .textSelection(.enabled)
                        }
                    }
                }
            } else {
                emptyHint(Strings.Harnesses.detailNoFocuses)
            }
        }
    }

    // MARK: - Helpers

    private func emptyHint(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
