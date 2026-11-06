import SwiftUI
import TermQShared

/// Read-only breakdown of a harness profile — its includes, hooks and MCP
/// servers — shown inline when a profile card is expanded.
struct HarnessProfileDetailsView: View {
    let profile: ComposedProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let includes = profile.includes, !includes.isEmpty {
                detailGroup(Strings.Harnesses.profileIncludes) {
                    ForEach(Array(includes.enumerated()), id: \.offset) { _, inc in
                        profileIncludeRow(inc)
                    }
                }
            }

            if let hooks = profile.hooks, !hooks.isEmpty {
                detailGroup(Strings.Harnesses.detailHooks) {
                    ForEach(hooks.keys.sorted(), id: \.self) { event in
                        ForEach(Array((hooks[event] ?? []).enumerated()), id: \.offset) { _, hook in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(event)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.orange)
                                Text(hook.command)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                if let matcher = hook.matcher, !matcher.isEmpty {
                                    Text("(\(matcher))")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            if let servers = profile.mcpServers, !servers.isEmpty {
                detailGroup(Strings.Harnesses.detailMCPServers) {
                    ForEach(servers.keys.sorted(), id: \.self) { name in
                        profileMCPRow(name, servers[name])
                    }
                }
            }
        }
    }

    private func detailGroup<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            content()
                .padding(.leading, 8)
        }
    }

    private func profileIncludeRow(_ inc: ComposedInclude) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: inc.resolved ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.system(size: 9))
                    .foregroundColor(inc.resolved ? .green : .orange)
                    .help(inc.resolved ? Strings.Harnesses.detailResolved : Strings.Harnesses.detailUnresolved)
                Text(GitURLHelper.shortURL(inc.git))
                    .font(.system(size: 11, weight: .medium))
                    .textSelection(.enabled)
                    .help(inc.git)
                if let ref = inc.ref, !ref.isEmpty {
                    Text("@\(ref)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            if let path = inc.path, !path.isEmpty {
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 13)
            }
            if let picks = inc.pick, !picks.isEmpty {
                Text("\(Strings.Harnesses.detailPicks(picks.count)) \(picks.joined(separator: ", "))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 13)
            }
        }
    }

    @ViewBuilder
    private func profileMCPRow(_ name: String, _ entry: ComposedProfileMCPEntry?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name)
                .font(.system(size: 11, weight: .medium))
            switch entry {
            case .server(let srv):
                if let cmd = srv.command, !cmd.isEmpty {
                    Text(([cmd] + (srv.args ?? [])).joined(separator: " "))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .padding(.leading, 8)
                }
                if let url = srv.url, !url.isEmpty {
                    Text(url)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .padding(.leading, 8)
                }
            case .nulled:
                Text(Strings.Harnesses.mcpNulledHint)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
            case .none:
                EmptyView()
            }
        }
    }
}
