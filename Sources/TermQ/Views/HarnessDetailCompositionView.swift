import SwiftUI
import TermQShared

/// Composition sections for the harness detail pane: hooks, MCP servers,
/// profiles, and focuses.
struct HarnessDetailCompositionView: View {
    let composition: HarnessComposition
    let harnessID: String
    var focusEditor: HarnessFocusEditor?
    var profileEditor: HarnessProfileEditor?
    var hookEditor: HarnessHookEditor?

    init(
        composition: HarnessComposition,
        harnessID: String,
        focusEditor: HarnessFocusEditor? = nil,
        profileEditor: HarnessProfileEditor? = nil,
        hookEditor: HarnessHookEditor? = nil
    ) {
        self.composition = composition
        self.harnessID = harnessID
        self.focusEditor = focusEditor
        self.profileEditor = profileEditor
        self.hookEditor = hookEditor
    }

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
        .modifier(
            OptionalFocusEditorOverlay(
                editor: focusEditor,
                harnessID: harnessID,
                availableProfiles: composition.profiles.keys.sorted()
            )
        )
        .modifier(OptionalProfileEditorOverlay(editor: profileEditor, harnessID: harnessID))
        .modifier(OptionalHookEditorOverlay(editor: hookEditor, harnessID: harnessID))
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

                            ForEach(Array(entries.enumerated()), id: \.offset) { idx, hook in
                                HStack(spacing: 6) {
                                    Text(hook.command)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)

                                    if let matcher = hook.matcher, !matcher.isEmpty {
                                        Text("(\(matcher))")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if let editor = hookEditor {
                                        Button {
                                            Task {
                                                await editor.confirmRemoveHook(
                                                    harnessID: harnessID, event: event, index: idx
                                                )
                                            }
                                        } label: {
                                            Image(systemName: "minus.circle")
                                                .font(.system(size: 11))
                                        }
                                        .buttonStyle(.borderless)
                                        .foregroundColor(.secondary)
                                        .disabled(editor.isMutating)
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

            if let editor = hookEditor {
                Button {
                    editor.requestAddHook()
                } label: {
                    Label(Strings.Harnesses.addHookButton, systemImage: "plus.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundColor(.accentColor)
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
                        HStack(alignment: .top, spacing: 6) {
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

                            Spacer()

                            if let editor = hookEditor {
                                Button {
                                    Task {
                                        await editor.confirmRemoveMCP(
                                            harnessID: harnessID, serverName: name
                                        )
                                    }
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.secondary)
                                .disabled(editor.isMutating)
                            }
                        }
                    }
                }
            } else {
                emptyHint(Strings.Harnesses.detailNoMCPServers)
            }

            if let editor = hookEditor {
                Button {
                    editor.requestAddMCP()
                } label: {
                    Label(Strings.Harnesses.addMCPButton, systemImage: "plus.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundColor(.accentColor)
            }
        }
    }

    // MARK: - Profiles

    private func profilesSection(_ profiles: [String: ComposedProfile]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Harnesses.detailProfiles)
                .font(.headline)

            if !profiles.isEmpty {
                ForEach(profiles.keys.sorted(), id: \.self) { name in
                    if let profile = profiles[name] {
                        profileCard(name, profile)
                    }
                }
            } else {
                emptyHint(Strings.Harnesses.detailNoProfiles)
            }

            if let editor = profileEditor {
                Button {
                    editor.requestAdd()
                } label: {
                    Label(Strings.Harnesses.addProfileButton, systemImage: "plus.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundColor(.accentColor)
            }
        }
    }

    @ViewBuilder
    private func profileCard(_ name: String, _ profile: ComposedProfile) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())

                let summary = profileSummary(profile)
                if !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                }
            }

            if let editor = profileEditor {
                Spacer()
                Menu {
                    Button(Strings.Harnesses.editProfileButton) {
                        editor.requestEdit(ProfileEditTarget(name: name, profile: profile))
                    }
                    Divider()
                    Button(Strings.Harnesses.removeProfileButton, role: .destructive) {
                        editor.requestRemove(ProfileEditTarget(name: name, profile: profile))
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private func profileSummary(_ profile: ComposedProfile) -> String {
        var parts: [String] = []
        let hookCount = profile.hooks?.values.reduce(0) { $0 + $1.count } ?? 0
        if hookCount > 0 { parts.append("\(hookCount) hook\(hookCount == 1 ? "" : "s")") }
        let mcpCount = profile.mcpServers?.count ?? 0
        if mcpCount > 0 { parts.append("\(mcpCount) MCP") }
        let incCount = profile.includes?.count ?? 0
        if incCount > 0 { parts.append("\(incCount) include\(incCount == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Focuses

    private func focusesSection(_ focuses: [String: ComposedFocus]?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Harnesses.detailFocuses)
                .font(.headline)

            if let focuses, !focuses.isEmpty {
                ForEach(focuses.keys.sorted(), id: \.self) { name in
                    if let focus = focuses[name] {
                        focusRow(name, focus)
                    }
                }
            } else {
                emptyHint(Strings.Harnesses.detailNoFocuses)
            }

            if let editor = focusEditor {
                Button {
                    editor.requestAdd()
                } label: {
                    Label(Strings.Harnesses.addFocusButton, systemImage: "plus.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundColor(.accentColor)
            }
        }
    }

    @ViewBuilder
    private func focusRow(_ name: String, _ focus: ComposedFocus) -> some View {
        HStack(alignment: .firstTextBaseline) {
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

            if let editor = focusEditor {
                Spacer()
                Menu {
                    Button(Strings.Harnesses.editFocusButton) {
                        editor.requestEdit(
                            FocusEditTarget(
                                name: name, prompt: focus.prompt, profile: focus.profile
                            ))
                    }
                    Divider()
                    Button(Strings.Harnesses.removeFocusButton, role: .destructive) {
                        editor.requestRemove(
                            FocusEditTarget(
                                name: name, prompt: focus.prompt, profile: focus.profile
                            ))
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
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

// MARK: - Optional editor overlay helpers

private struct OptionalFocusEditorOverlay: ViewModifier {
    let editor: HarnessFocusEditor?
    let harnessID: String
    let availableProfiles: [String]

    func body(content: Content) -> some View {
        if let editor {
            content.modifier(
                FocusEditorOverlay(
                    editor: editor,
                    harnessID: harnessID,
                    availableProfiles: availableProfiles
                ))
        } else {
            content
        }
    }
}

private struct OptionalProfileEditorOverlay: ViewModifier {
    let editor: HarnessProfileEditor?
    let harnessID: String

    func body(content: Content) -> some View {
        if let editor {
            content.modifier(ProfileEditorOverlay(editor: editor, harnessID: harnessID))
        } else {
            content
        }
    }
}

private struct OptionalHookEditorOverlay: ViewModifier {
    let editor: HarnessHookEditor?
    let harnessID: String

    func body(content: Content) -> some View {
        if let editor {
            content.modifier(HarnessHookEditorOverlay(editor: editor, harnessID: harnessID))
        } else {
            content
        }
    }
}
