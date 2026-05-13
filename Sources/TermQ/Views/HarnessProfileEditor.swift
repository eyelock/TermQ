import SwiftUI
import TermQShared

struct ProfileEditTarget: Identifiable {
    var id: String { name }
    let name: String
    let profile: ComposedProfile
}

@MainActor
final class HarnessProfileEditor: ObservableObject {
    @Published var editingTarget: ProfileEditTarget?
    @Published var removalTarget: ProfileEditTarget?
    @Published var isAddingProfile = false
    @Published private(set) var isMutating = false
    @Published var errorMessage: String?

    private let repository: HarnessRepository
    private let detector: any YNHDetectorProtocol
    private let mutator: ProfileMutator

    init(
        detector: any YNHDetectorProtocol = YNHDetector.shared,
        repository: HarnessRepository = .shared,
        mutator: ProfileMutator = ProfileMutator()
    ) {
        self.detector = detector
        self.repository = repository
        self.mutator = mutator
    }

    func requestAdd() {
        errorMessage = nil
        isAddingProfile = true
    }

    func requestEdit(_ target: ProfileEditTarget) {
        errorMessage = nil
        editingTarget = target
    }

    func requestRemove(_ target: ProfileEditTarget) {
        errorMessage = nil
        removalTarget = target
    }

    func confirmAdd(harnessID: String, name: String) async {
        guard let ynhPath = readyYnhPath() else { return }
        isMutating = true
        await mutator.addProfile(
            ProfileAddOptions(harness: harnessID, name: name),
            ynhPath: ynhPath, environment: ynhEnvironment()
        )
        isMutating = false

        if mutator.succeeded {
            isAddingProfile = false
            await reloadDetail(harnessID: harnessID)
        } else {
            errorMessage = mutator.errorMessage
        }
    }

    func confirmRemove(target: ProfileEditTarget, harnessID: String) async {
        guard let ynhPath = readyYnhPath() else { return }
        isMutating = true
        await mutator.removeProfile(
            ProfileRemoveOptions(harness: harnessID, name: target.name),
            ynhPath: ynhPath, environment: ynhEnvironment()
        )
        isMutating = false

        if mutator.succeeded {
            removalTarget = nil
            await reloadDetail(harnessID: harnessID)
        } else {
            errorMessage = mutator.errorMessage
        }
    }

    func addHook(harnessID: String, profileName: String, event: String, command: String, matcher: String?) async {
        guard let ynhPath = readyYnhPath() else { return }
        isMutating = true
        await mutator.addHook(
            ProfileHookAddOptions(
                harness: harnessID, profileName: profileName, event: event, command: command, matcher: matcher),
            ynhPath: ynhPath, environment: ynhEnvironment()
        )
        isMutating = false
        if mutator.succeeded {
            await reloadAndRefresh(harnessID: harnessID)
        } else {
            errorMessage = mutator.errorMessage
        }
    }

    func removeHook(harnessID: String, profileName: String, event: String, index: Int) async {
        guard let ynhPath = readyYnhPath() else { return }
        isMutating = true
        await mutator.removeHook(
            ProfileHookRemoveOptions(harness: harnessID, profileName: profileName, event: event, index: index),
            ynhPath: ynhPath, environment: ynhEnvironment()
        )
        isMutating = false
        if mutator.succeeded {
            await reloadAndRefresh(harnessID: harnessID)
        } else {
            errorMessage = mutator.errorMessage
        }
    }

    func addMCP(harnessID: String, profileName: String, result: MCPAddResult) async {
        guard let ynhPath = readyYnhPath() else { return }
        isMutating = true
        await mutator.addMCP(
            ProfileMCPAddOptions(
                harness: harnessID, profileName: profileName,
                serverName: result.name, command: result.command,
                args: result.args, env: [:], url: result.url, headers: [:], null: false
            ),
            ynhPath: ynhPath, environment: ynhEnvironment()
        )
        isMutating = false
        if mutator.succeeded {
            await reloadAndRefresh(harnessID: harnessID)
        } else {
            errorMessage = mutator.errorMessage
        }
    }

    func removeMCP(harnessID: String, profileName: String, serverName: String) async {
        guard let ynhPath = readyYnhPath() else { return }
        isMutating = true
        await mutator.removeMCP(
            ProfileMCPRemoveOptions(harness: harnessID, profileName: profileName, serverName: serverName),
            ynhPath: ynhPath, environment: ynhEnvironment()
        )
        isMutating = false
        if mutator.succeeded {
            await reloadAndRefresh(harnessID: harnessID)
        } else {
            errorMessage = mutator.errorMessage
        }
    }

    func addInclude(_ opts: ProfileIncludeAddOptions) async -> Bool {
        guard let ynhPath = readyYnhPath() else { return false }
        isMutating = true
        await mutator.addInclude(opts, ynhPath: ynhPath, environment: ynhEnvironment())
        isMutating = false
        if mutator.succeeded {
            await reloadAndRefresh(harnessID: opts.harness)
            return true
        }
        return false
    }

    func removeInclude(harnessID: String, profileName: String, url: String, path: String?) async {
        guard let ynhPath = readyYnhPath() else { return }
        isMutating = true
        await mutator.removeInclude(
            ProfileIncludeRemoveOptions(harness: harnessID, profileName: profileName, url: url, path: path),
            ynhPath: ynhPath, environment: ynhEnvironment()
        )
        isMutating = false
        if mutator.succeeded {
            await reloadAndRefresh(harnessID: harnessID)
        } else {
            errorMessage = mutator.errorMessage
        }
    }

    private func reloadAndRefresh(harnessID: String) async {
        await reloadDetail(harnessID: harnessID)
        guard let targetName = editingTarget?.name,
            let profile = repository.cachedDetail(for: harnessID)?.composition.profiles[targetName]
        else { return }
        editingTarget = ProfileEditTarget(name: targetName, profile: profile)
    }

    private func reloadDetail(harnessID: String) async {
        repository.invalidateDetail(for: harnessID)
        await repository.fetchDetail(for: harnessID)
    }

    private func readyYnhPath() -> String? {
        if case .ready(let ynhPath, _, _) = detector.status { return ynhPath }
        errorMessage = "YNH toolchain is not ready"
        return nil
    }

    private func ynhEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let override = detector.ynhHomeOverride {
            env["YNH_HOME"] = override
        }
        return env
    }
}

// MARK: - Add Profile Sheet

struct AddProfileSheet: View {
    @ObservedObject var editor: HarnessProfileEditor
    let harnessID: String

    @State private var nameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Strings.Harnesses.addProfileTitle)
                .font(.headline)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Strings.Harnesses.profileName)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)
                TextField(Strings.Harnesses.profileNamePlaceholder, text: $nameText)
                    .textFieldStyle(.roundedBorder)
            }

            if let error = editor.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button(Strings.Harnesses.focusCancelButton) {
                    editor.isAddingProfile = false
                    editor.errorMessage = nil
                }
                .keyboardShortcut(.cancelAction)

                Button(Strings.Harnesses.profileAddButton) {
                    Task {
                        await editor.confirmAdd(
                            harnessID: harnessID,
                            name: nameText.trimmingCharacters(in: .whitespaces)
                        )
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(nameText.trimmingCharacters(in: .whitespaces).isEmpty || editor.isMutating)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

// MARK: - Profile Detail Sheet

struct EditProfileSheet: View {
    @ObservedObject var editor: HarnessProfileEditor
    let harnessID: String
    let target: ProfileEditTarget

    @State private var showAddHookSheet = false
    @State private var showAddMCPSheet = false
    @State private var showAddIncludeSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(Strings.Harnesses.editProfileTitle(target.name))
                    .font(.headline)

                if let error = editor.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                hooksSection
                Divider()
                mcpSection
                Divider()
                includesSection

                HStack {
                    Spacer()
                    Button(Strings.Harnesses.editProfileDoneButton) {
                        editor.editingTarget = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 520)
        .frame(minHeight: 400)
        .sheet(isPresented: $showAddHookSheet) {
            AddHookSheet(
                onAdd: { event, command, matcher in
                    showAddHookSheet = false
                    addHook(event: event, command: command, matcher: matcher)
                },
                onCancel: { showAddHookSheet = false }
            )
        }
        .sheet(isPresented: $showAddMCPSheet) {
            AddMCPSheet(
                title: Strings.Harnesses.addMCPTitle,
                onAdd: { result in
                    showAddMCPSheet = false
                    addMCP(result)
                },
                onCancel: { showAddMCPSheet = false }
            )
        }
        .sheet(isPresented: $showAddIncludeSheet) {
            AddProfileIncludeSheetHost(
                harnessID: harnessID,
                profileName: target.name,
                editor: editor
            )
            .frame(width: 520, height: 620)
        }
    }

    // MARK: Hooks

    private var hooksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Harnesses.detailHooks)
                .font(.subheadline.weight(.semibold))

            let hooks = target.profile.hooks ?? [:]
            if hooks.isEmpty {
                emptyHint(Strings.Harnesses.detailNoHooks)
            } else {
                ForEach(hooks.keys.sorted(), id: \.self) { event in
                    if let entries = hooks[event] {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.orange)

                            ForEach(Array(entries.enumerated()), id: \.offset) { idx, hook in
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(hook.command)
                                            .font(.system(size: 11, design: .monospaced))
                                            .textSelection(.enabled)
                                        if let matcher = hook.matcher, !matcher.isEmpty {
                                            Text("matcher: \(matcher)")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        removeHook(event: event, index: idx)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(editor.isMutating)
                                }
                                .padding(.leading, 12)
                            }
                        }
                    }
                }
            }

            Button {
                showAddHookSheet = true
            } label: {
                Label(Strings.Harnesses.addHookButton, systemImage: "plus.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundColor(.accentColor)
        }
    }

    // MARK: MCP Servers

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Harnesses.detailMCPServers)
                .font(.subheadline.weight(.semibold))

            let servers = target.profile.mcpServers ?? [:]
            if servers.isEmpty {
                emptyHint(Strings.Harnesses.detailNoMCPServers)
            } else {
                ForEach(servers.keys.sorted(), id: \.self) { name in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.system(size: 12, weight: .medium))

                            switch servers[name] {
                            case .server(let srv):
                                if let cmd = srv.command, !cmd.isEmpty {
                                    Text(([cmd] + (srv.args ?? [])).joined(separator: " "))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                        .padding(.leading, 12)
                                }
                                if let url = srv.url, !url.isEmpty {
                                    Text(url)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                        .padding(.leading, 12)
                                }
                            case .nulled:
                                Text(Strings.Harnesses.mcpNulledHint)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 12)
                            case .none:
                                EmptyView()
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            removeMCP(serverName: name)
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .disabled(editor.isMutating)
                    }
                }
            }

            Button {
                showAddMCPSheet = true
            } label: {
                Label(Strings.Harnesses.addMCPButton, systemImage: "plus.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundColor(.accentColor)
        }
    }

    // MARK: Includes

    private var includesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Strings.Harnesses.profileIncludes)
                .font(.subheadline.weight(.semibold))

            let includes = target.profile.includes ?? []
            if includes.isEmpty {
                emptyHint(Strings.Harnesses.detailNoIncludes)
            } else {
                ForEach(Array(includes.enumerated()), id: \.element.git) { _, inc in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(GitURLHelper.shortURL(inc.git))
                                .font(.system(size: 12, weight: .medium))
                                .textSelection(.enabled)
                            if let ref = inc.ref, !ref.isEmpty {
                                Text(ref)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 12)
                            }
                            if let path = inc.path, !path.isEmpty {
                                Text(path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 12)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            removeInclude(url: inc.git, path: inc.path)
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .disabled(editor.isMutating)
                    }
                }
            }

            Button {
                showAddIncludeSheet = true
            } label: {
                Label(Strings.Harnesses.addProfileIncludeButton, systemImage: "plus.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundColor(.accentColor)
        }
    }

    // MARK: - Mutations

    private func addHook(event: String, command: String, matcher: String?) {
        Task {
            await editor.addHook(
                harnessID: harnessID, profileName: target.name, event: event, command: command, matcher: matcher)
        }
    }

    private func removeHook(event: String, index: Int) {
        Task { await editor.removeHook(harnessID: harnessID, profileName: target.name, event: event, index: index) }
    }

    private func addMCP(_ result: MCPAddResult) {
        Task { await editor.addMCP(harnessID: harnessID, profileName: target.name, result: result) }
    }

    private func removeMCP(serverName: String) {
        Task { await editor.removeMCP(harnessID: harnessID, profileName: target.name, serverName: serverName) }
    }

    private func removeInclude(url: String, path: String?) {
        Task { await editor.removeInclude(harnessID: harnessID, profileName: target.name, url: url, path: path) }
    }

    private func emptyHint(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

// MARK: - Overlay modifier

struct ProfileEditorOverlay: ViewModifier {
    @ObservedObject var editor: HarnessProfileEditor
    let harnessID: String

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $editor.isAddingProfile) {
                AddProfileSheet(editor: editor, harnessID: harnessID)
            }
            .sheet(item: $editor.editingTarget) { target in
                EditProfileSheet(editor: editor, harnessID: harnessID, target: target)
            }
            .confirmationDialog(
                Strings.Harnesses.removeProfileConfirmTitle,
                isPresented: Binding(
                    get: { editor.removalTarget != nil },
                    set: { if !$0 { editor.removalTarget = nil } }
                ),
                presenting: editor.removalTarget
            ) { target in
                Button(Strings.Harnesses.removeProfileConfirmButton, role: .destructive) {
                    Task { await editor.confirmRemove(target: target, harnessID: harnessID) }
                }
                Button(Strings.Harnesses.focusCancelButton, role: .cancel) {
                    editor.removalTarget = nil
                }
            } message: { target in
                Text(Strings.Harnesses.removeProfileConfirmMessage(target.name))
            }
    }
}
