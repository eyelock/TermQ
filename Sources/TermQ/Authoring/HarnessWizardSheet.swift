import AppKit
import SwiftUI
import TermQShared

/// Two-step wizard for scaffolding a new harness.
///
/// Step 1 — Identity & Destination: name, description, vendor, destination, install checkbox.
/// Step 2 — Create: runs `ynd create harness <name>` + optional `ynh install`, streams output.
/// Success overlay: primary CTA navigates to Marketplaces with HarnessIncludePicker pre-targeted.
struct HarnessWizardSheet: View {
    @ObservedObject var detector: YNHDetector
    @ObservedObject var harnessRepository: HarnessRepository
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var vendorService: VendorService = .shared
    @ObservedObject private var store: MarketplaceStore = .shared
    @StateObject private var author = HarnessAuthor()

    // Step 1 state
    @State private var name = ""
    @State private var description = ""
    @State private var selectedVendorID: String = ""
    @State private var destination = ""
    @State private var installAfterCreate = true
    @State private var nameError: String?

    // Navigation
    @State private var step: WizardStep = .identity

    enum WizardStep { case identity, create }

    private var ynhPath: String? {
        if case .ready(let ynhPath, _, _) = detector.status { return ynhPath }
        return nil
    }
    private var yndPath: String? {
        if case .ready(_, let yndPath, _) = detector.status { return yndPath }
        return nil
    }
    private var ynhEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let override = YNHDetector.shared.ynhHomeOverride { env["YNH_HOME"] = override }
        return env
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedDest: String { destination.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            wizardHeader
            Divider()

            switch step {
            case .identity: identityStep
            case .create:
                if author.succeeded {
                    successOverlay
                } else {
                    createStep
                }
            }

            Divider()
            footerButtons
        }
        .frame(width: 500, height: 440)
        .onAppear {
            Task { await vendorService.refresh() }
            loadDefaultDestination()
        }
    }

    // MARK: - Header

    private var wizardHeader: some View {
        HStack {
            Text(Strings.HarnessWizard.title)
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2).foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Step 1: Identity

    private var identityStep: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("", text: $name, prompt: Text("my-harness"))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: name) { _, _ in nameError = nil }
                    if let err = nameError {
                        Text(err).font(.caption).foregroundColor(.red)
                    }
                }
            } header: {
                Text(Strings.HarnessWizard.nameLabel)
            }

            Section {
                TextField("Optional description", text: $description)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text(Strings.HarnessWizard.descriptionLabel)
            }

            Section {
                if vendorService.vendors.isEmpty {
                    Text(Strings.HarnessWizard.loadingVendors)
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Picker(Strings.HarnessWizard.vendorLabel, selection: $selectedVendorID) {
                        ForEach(vendorService.vendors) { vendor in
                            Text(vendor.displayName).tag(vendor.vendorID)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: vendorService.vendors.count) { _, _ in
                        if selectedVendorID.isEmpty, let first = vendorService.vendors.first {
                            selectedVendorID = first.vendorID
                        }
                    }
                }
            } header: {
                Text(Strings.HarnessWizard.vendorLabel)
            }

            Section {
                HStack {
                    TextField("/path/to/harnesses", text: $destination)
                        .textFieldStyle(.roundedBorder)
                    Button(Strings.Common.browse) { browseDestination() }
                }
            } header: {
                Text(Strings.HarnessWizard.destinationLabel)
            }

            Section {
                Toggle(Strings.HarnessWizard.installToggle, isOn: $installAfterCreate)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Step 2: Create

    private var createStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Per-step status
            VStack(alignment: .leading, spacing: 8) {
                ForEach(author.steps) { step in
                    HStack(spacing: 8) {
                        stepStatusIcon(step.status)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.label).font(.body)
                            Text(step.command)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()

            Divider()

            // Output stream
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(author.outputLines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                                .id(idx)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: author.outputLines.count) { _, count in
                    if count > 0 { proxy.scrollTo(count - 1) }
                }
            }
        }
    }

    @ViewBuilder
    private func stepStatusIcon(_ status: AuthorStepStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle").foregroundColor(.secondary)
        case .running:
            ProgressView().controlSize(.small).frame(width: 16, height: 16)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        }
    }

    // MARK: - Success overlay

    private var successOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52)).foregroundColor(.green)
            Text(Strings.HarnessWizard.successCreated(author.createdHarnessName ?? trimmedName))
                .font(.title3).fontWeight(.semibold)

            VStack(spacing: 8) {
                Button(Strings.HarnessWizard.successAddPlugins) {
                    if let harnessName = author.createdHarnessName {
                        store.preselectedHarnessTarget = harnessName
                    }
                    sidebarTab = "marketplaces"  // matches SidebarView.SidebarTab.marketplaces.rawValue
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

                HStack(spacing: 12) {
                    if let harnessName = author.createdHarnessName {
                        Button(Strings.HarnessWizard.successOpen) {
                            harnessRepository.selectedHarnessName = harnessName
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                    Button(Strings.Sidebar.revealInFinder) {
                        let path = (trimmedDest as NSString).appendingPathComponent(trimmedName)
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [URL(fileURLWithPath: path)]
                        )
                    }
                    .buttonStyle(.bordered)
                    Button(Strings.Common.close) { dismiss() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Footer

    private var footerButtons: some View {
        HStack {
            if step == .create && !author.succeeded {
                Button(Strings.Common.close) { dismiss() }
                    .disabled(author.isRunning)
            } else if step == .identity {
                Button(Strings.Common.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            if step == .identity {
                Button(Strings.HarnessWizard.create) { beginCreate() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            } else if step == .create, case .failed = author.steps.last?.status {
                Button(Strings.HarnessWizard.retry) {
                    Task { await runAuthor() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private var canCreate: Bool {
        !trimmedName.isEmpty
            && !selectedVendorID.isEmpty
            && !trimmedDest.isEmpty
            && yndPath != nil
            && (installAfterCreate ? ynhPath != nil : true)
    }

    // MARK: - Actions

    private func beginCreate() {
        guard validate() else { return }
        step = .create
        Task { await runAuthor() }
    }

    private func runAuthor() async {
        guard let ynd = yndPath, let ynh = ynhPath ?? (installAfterCreate ? nil : "") else { return }
        let ynhBin = installAfterCreate ? (ynhPath ?? "") : ynh
        await author.run(
            name: trimmedName,
            description: description.trimmingCharacters(in: .whitespaces),
            vendorID: selectedVendorID,
            destination: trimmedDest,
            install: installAfterCreate,
            yndPath: ynd,
            ynhPath: ynhBin,
            environment: ynhEnvironment
        )
        if author.succeeded {
            await harnessRepository.refresh()
        }
    }

    private func validate() -> Bool {
        if trimmedName.isEmpty {
            nameError = Strings.HarnessWizard.errorNameRequired
            return false
        }
        let forbidden = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted
        if trimmedName.rangeOfCharacter(from: forbidden) != nil {
            nameError = Strings.HarnessWizard.errorNameInvalid
            return false
        }
        if harnessRepository.harnesses.contains(where: { $0.name == trimmedName }) {
            nameError = Strings.HarnessWizard.errorNameDuplicate(trimmedName)
            return false
        }
        return true
    }

    private func browseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        Task {
            let response = await panel.begin()
            if response == .OK, let url = panel.url {
                destination = url.path(percentEncoded: false)
            }
        }
    }

    @AppStorage("defaultHarnessAuthorDirectory") private var defaultHarnessAuthorDirectory = ""
    @AppStorage("sidebar.selectedTab") private var sidebarTab = "repositories"

    private func loadDefaultDestination() {
        if !defaultHarnessAuthorDirectory.isEmpty {
            destination = defaultHarnessAuthorDirectory
            return
        }
        if case .ready(_, _, let paths) = detector.status {
            destination = paths.harnesses
        }
    }
}
