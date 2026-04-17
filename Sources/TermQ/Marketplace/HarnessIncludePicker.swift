import SwiftUI
import TermQShared

/// Reusable multi-step view for adding a marketplace plugin to an existing harness.
///
/// Modes:
/// - `.standalone`: full 3-step flow (pick skills → choose harness → review & apply)
/// - `.wizard(harnessName:)`: skips step 2 (harness already known); used from `HarnessWizardSheet`
struct HarnessIncludePicker: View {
    let plugin: MarketplacePlugin
    let marketplace: Marketplace
    @ObservedObject var harnessRepository: HarnessRepository
    @ObservedObject var detector: YNHDetector
    var mode: PickerMode = .standalone
    var onDone: () -> Void

    enum PickerMode {
        case standalone
        case wizard(harnessName: String)
    }

    enum Step { case skills, chooseHarness, review }

    @State private var step: Step = .skills
    @State private var selectedPicks: Set<String> = []
    @State private var targetHarnessName: String?
    @StateObject private var applier = IncludeApplier()
    @State private var applied = false
    @State private var isLoadingPicks = false
    @State private var resolvedPicks: [String] = []

    private var ynhPath: String? {
        if case .ready(let p, _, _) = detector.status { return p }
        return nil
    }

    private var ynhEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let override = YNHDetector.shared.ynhHomeOverride { env["YNH_HOME"] = override }
        return env
    }

    var body: some View {
        VStack(spacing: 0) {
            stepHeader
            Divider()
            stepContent
            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 420)
        .navigationTitle(plugin.name)
        .navigationBarBackButtonHidden()
        .onAppear {
            resolvedPicks = plugin.picks
            selectedPicks = Set(plugin.picks)
            if case .wizard(let name) = mode {
                targetHarnessName = name
            }
            let needsLoad =
                plugin.skillsState == .pending
                || (plugin.skillsState == .eager && plugin.picks.isEmpty && plugin.source.type.isExternal)
            if needsLoad {
                isLoadingPicks = true
                Task { await loadPicks() }
            }
        }
    }

    // MARK: - Step header

    private var stepHeader: some View {
        HStack(spacing: 16) {
            stepIndicator(
                index: 0, label: Strings.Marketplace.Picker.stepArtifacts, current: step == .skills,
                done: step != .skills)
            stepDivider
            if case .standalone = mode {
                stepIndicator(
                    index: 1, label: Strings.Marketplace.Picker.stepHarness, current: step == .chooseHarness,
                    done: step == .review || applied)
                stepDivider
                stepIndicator(
                    index: 2, label: Strings.Marketplace.Picker.stepApply, current: step == .review, done: applied)
            } else {
                stepIndicator(
                    index: 1, label: Strings.Marketplace.Picker.stepApply, current: step == .review, done: applied)
            }
        }
        .padding()
    }

    private func stepIndicator(index: Int, label: String, current: Bool, done: Bool) -> some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(current ? Color.accentColor : (done ? Color.green : Color.secondary.opacity(0.3)))
                    .frame(width: 22, height: 22)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                } else {
                    Text("\(index + 1)").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                }
            }
            Text(label)
                .font(.caption)
                .foregroundColor(current ? .primary : .secondary)
        }
    }

    private var stepDivider: some View {
        Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1).frame(maxWidth: .infinity)
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .skills:
            skillsStep
        case .chooseHarness:
            chooseHarnessStep
        case .review:
            if applied {
                successState
            } else if applier.isRunning {
                progressState
            } else {
                reviewStep
            }
        }
    }

    // MARK: - Step 1: Skills

    private var skillsStep: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Strings.Marketplace.Picker.selectPrompt)
                    .font(.subheadline).foregroundColor(.secondary)
                Spacer()
                Button(Strings.Marketplace.Picker.selectAll) { selectedPicks = Set(resolvedPicks) }
                    .buttonStyle(.plain).foregroundColor(.accentColor).font(.caption)
                Text("·").foregroundColor(.secondary).font(.caption)
                Button(Strings.Marketplace.Picker.selectNone) { selectedPicks = [] }
                    .buttonStyle(.plain).foregroundColor(.accentColor).font(.caption)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider()

            if isLoadingPicks {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(Strings.Marketplace.pluginLoadingArtifacts)
                        .font(.callout).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if resolvedPicks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "puzzlepiece").font(.system(size: 28)).foregroundColor(.secondary)
                    Text(Strings.Marketplace.pluginNoArtifacts)
                        .font(.callout).foregroundColor(.secondary)
                    Text(Strings.Marketplace.pluginNoArtifactsHint)
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(resolvedPicks, id: \.self) { skill in
                    HStack {
                        Image(systemName: selectedPicks.contains(skill) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedPicks.contains(skill) ? .accentColor : .secondary)
                        Text(skill).font(.body)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedPicks.contains(skill) {
                            selectedPicks.remove(skill)
                        } else {
                            selectedPicks.insert(skill)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Step 2: Choose harness (standalone only)

    private var chooseHarnessStep: some View {
        VStack(spacing: 0) {
            if harnessRepository.harnesses.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 32)).foregroundColor(.secondary)
                    Text(Strings.Marketplace.Picker.noHarnesses)
                        .font(.callout).foregroundColor(.secondary)
                    Text(Strings.Marketplace.Picker.noHarnessesHint)
                        .font(.caption).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(harnessRepository.harnesses, selection: $targetHarnessName) {
                    harness in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(harness.name).font(.body)
                        if let desc = harness.description {
                            Text(desc).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                    .tag(harness.name)
                    .padding(.vertical, 2)
                }
                .listStyle(.sidebar)
            }
        }
    }

    // MARK: - Step 3: Review

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                LabeledContent(Strings.Marketplace.Picker.reviewPlugin, value: plugin.name)
                LabeledContent(Strings.Marketplace.Picker.reviewHarness, value: targetHarnessName ?? "—")
                if !resolvedPicks.isEmpty {
                    LabeledContent(Strings.Marketplace.Picker.reviewArtifacts) {
                        if selectedPicks.count == resolvedPicks.count {
                            Text(Strings.Marketplace.Picker.reviewAllCount(selectedPicks.count))
                        } else {
                            Text(Strings.Marketplace.Picker.reviewSelected(selectedPicks.count, resolvedPicks.count))
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.Marketplace.Picker.commandPreview).font(.caption).foregroundColor(.secondary)
                Text(commandPreview)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if let err = applier.errorMessage {
                Label(err, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundColor(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var commandPreview: String {
        var parts = ["ynh", "include", "add", targetHarnessName ?? "<harness>", plugin.source.url]
        if let p = plugin.source.path { parts += ["--path", p] }
        let pick = Array(selectedPicks).sorted()
        if !pick.isEmpty && pick.count < resolvedPicks.count {
            let bareNames = pick.map { $0.components(separatedBy: "/").last ?? $0 }
            parts += ["--pick", bareNames.joined(separator: ",")]
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Progress & success

    private var progressState: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(applier.outputLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                                .id(line)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: applier.outputLines.count) { _, _ in
                    if let last = applier.outputLines.last { proxy.scrollTo(last) }
                }
            }
        }
    }

    private var successState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44)).foregroundColor(.green)
            Text(Strings.Marketplace.Picker.success(targetHarnessName ?? "harness"))
                .font(.headline)
            Text(plugin.name).font(.subheadline).foregroundColor(.secondary)
            Button(Strings.Marketplace.Picker.done) { onDone() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step != .skills && !applied && !applier.isRunning {
                Button(Strings.Marketplace.Picker.back) { goBack() }
            }
            Spacer()
            Button(Strings.Common.cancel) { onDone() }
                .keyboardShortcut(.cancelAction)
                .disabled(applier.isRunning)
            if !applied && !applier.isRunning {
                Button(nextLabel) { advance() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvance)
            }
        }
        .padding()
    }

    private var nextLabel: String {
        switch step {
        case .skills: return Strings.Marketplace.Picker.next
        case .chooseHarness: return Strings.Marketplace.Picker.next
        case .review: return Strings.Marketplace.Picker.stepApply
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .skills: return !isLoadingPicks
        case .chooseHarness: return targetHarnessName != nil
        case .review: return ynhPath != nil && targetHarnessName != nil
        }
    }

    private func advance() {
        switch step {
        case .skills:
            if case .standalone = mode { step = .chooseHarness } else { step = .review }
        case .chooseHarness:
            step = .review
        case .review:
            Task { await applyInclude() }
        }
    }

    private func goBack() {
        switch step {
        case .chooseHarness: step = .skills
        case .review:
            if case .standalone = mode { step = .chooseHarness } else { step = .skills }
        case .skills: break
        }
    }

    private func loadPicks() async {
        let needsLoad =
            plugin.skillsState == .pending
            || (plugin.skillsState == .eager && plugin.picks.isEmpty && plugin.source.type.isExternal)
        guard needsLoad else { return }
        isLoadingPicks = true
        defer { isLoadingPicks = false }
        do {
            let picks = try await MarketplaceFetcher.fetchSkills(for: plugin)
            // Update the store so the detail view also sees the result
            var updated = marketplace
            if let idx = updated.plugins.firstIndex(where: { $0.id == plugin.id }) {
                updated.plugins[idx].picks = picks
                updated.plugins[idx].skillsState = .eager
                MarketplaceStore.shared.update(updated)
            }
            resolvedPicks = picks
            selectedPicks = Set(picks)
            if picks.isEmpty { advance() }
        } catch {
            var updated = marketplace
            if let idx = updated.plugins.firstIndex(where: { $0.id == plugin.id }) {
                updated.plugins[idx].skillsState = .failed(error.localizedDescription)
                MarketplaceStore.shared.update(updated)
            }
        }
    }

    private func applyInclude() async {
        guard let ynhPath, let harness = targetHarnessName else { return }
        let pick: [String]
        if selectedPicks.isEmpty || selectedPicks.count == resolvedPicks.count {
            pick = []
        } else {
            pick = Array(selectedPicks).sorted()
        }

        await applier.apply(
            harness: harness,
            sourceURL: plugin.source.url,
            path: plugin.source.path,
            pick: pick,
            ynhPath: ynhPath,
            environment: ynhEnvironment
        )

        if applier.succeeded {
            harnessRepository.invalidateDetail(for: harness)
            applied = true
        }
    }
}
