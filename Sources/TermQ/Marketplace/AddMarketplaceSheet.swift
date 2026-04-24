import SwiftUI

/// Sheet for adding a new marketplace — known seeds or custom Git URL.
struct AddMarketplaceSheet: View {
    let onAdd: (Marketplace) -> Void
    @Environment(\.dismiss) private var dismiss

    enum AddTab { case known, custom, local }
    @State private var tab: AddTab = .known
    @State private var customURL = ""
    @State private var customVendor: MarketplaceVendor = .claude
    @State private var customName = ""
    @State private var customRef = ""
    @State private var localPath = ""
    @State private var localVendor: MarketplaceVendor = .claude
    @State private var localName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Strings.Marketplace.addSheetTitle)
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            Picker("", selection: $tab) {
                Text(Strings.Marketplace.addTabKnown).tag(AddTab.known)
                Text(Strings.Marketplace.addTabCustom).tag(AddTab.custom)
                Text(Strings.Marketplace.addTabLocal).tag(AddTab.local)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            switch tab {
            case .known: knownTab
            case .custom: customTab
            case .local: localTab
            }
        }
        .frame(width: 460, height: 400)
    }

    // MARK: - Known seeds

    private var knownTab: some View {
        VStack(spacing: 0) {
            List(KnownMarketplaces.all, id: \.url) { seed in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(seed.name).font(.body).fontWeight(.medium)
                            Text(seed.vendor.displayName)
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundColor(.accentColor)
                                .clipShape(Capsule())
                        }
                        Text(seed.description)
                            .font(.caption).foregroundColor(.secondary).lineLimit(2)
                        Text(seed.url)
                            .font(.caption2).foregroundColor(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button(Strings.Common.add) {
                        let marketplace = Marketplace(
                            id: UUID(), name: seed.name, owner: seed.owner,
                            description: seed.description, vendor: seed.vendor,
                            url: seed.url, ref: nil, plugins: [], lastFetched: nil, fetchError: nil
                        )
                        onAdd(marketplace)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)

            Divider()

            HStack {
                Button(Strings.Common.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Custom URL

    private var customTab: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("https://github.com/owner/repo", text: $customURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: customURL) { _, val in
                            if customName.isEmpty {
                                customName = Self.extractOrgRepo(from: val)
                            }
                        }
                    TextField(Strings.Marketplace.addRefPlaceholder, text: $customRef)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text(Strings.Marketplace.addSectionGitURL)
                }

                Section {
                    TextField(Strings.Marketplace.addCustomNamePlaceholder, text: $customName)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text(Strings.Marketplace.addSectionDisplayName)
                }

                Section {
                    Picker(Strings.Marketplace.addSectionVendor, selection: $customVendor) {
                        ForEach(MarketplaceVendor.allCases, id: \.self) { vendor in
                            Text(vendor.displayName).tag(vendor)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(Strings.Marketplace.addSectionVendor)
                }
            }
            .formStyle(.grouped)

            Spacer()

            HStack {
                Button(Strings.Common.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(Strings.Common.add) {
                    let trimURL = customURL.trimmingCharacters(in: .whitespaces)
                    let orgRepo = Self.extractOrgRepo(from: trimURL)
                    let name = customName.trimmingCharacters(in: .whitespaces)
                    let owner = orgRepo.components(separatedBy: "/").first ?? ""
                    let trimRef = customRef.trimmingCharacters(in: .whitespaces)
                    let marketplace = Marketplace(
                        id: UUID(),
                        name: name.isEmpty ? orgRepo : name,
                        owner: owner,
                        description: nil,
                        vendor: customVendor,
                        url: trimURL,
                        ref: trimRef.isEmpty ? nil : trimRef,
                        plugins: [],
                        lastFetched: nil,
                        fetchError: nil
                    )
                    onAdd(marketplace)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(customURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
    }

    // MARK: - Local Folder

    private var localTab: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack {
                        TextField(Strings.Marketplace.addLocalPathPlaceholder, text: $localPath)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: localPath) { _, val in
                                if localName.isEmpty {
                                    localName = URL(fileURLWithPath: val).lastPathComponent
                                }
                            }
                        Button(Strings.Marketplace.addLocalBrowse) {
                            Task { @MainActor in
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.allowsMultipleSelection = false
                                panel.canCreateDirectories = false
                                let response = await panel.begin()
                                if response == .OK, let url = panel.url {
                                    localPath = url.path
                                    if localName.isEmpty { localName = url.lastPathComponent }
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                } header: {
                    Text(Strings.Marketplace.addSectionLocalPath)
                }

                Section {
                    TextField(Strings.Marketplace.addCustomNamePlaceholder, text: $localName)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text(Strings.Marketplace.addSectionDisplayName)
                }

                Section {
                    Picker(Strings.Marketplace.addSectionVendor, selection: $localVendor) {
                        ForEach(MarketplaceVendor.allCases, id: \.self) { vendor in
                            Text(vendor.displayName).tag(vendor)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(Strings.Marketplace.addSectionVendor)
                }
            }
            .formStyle(.grouped)

            Spacer()

            HStack {
                Button(Strings.Common.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(Strings.Common.add) {
                    let trimPath = localPath.trimmingCharacters(in: .whitespaces)
                    let name = localName.trimmingCharacters(in: .whitespaces)
                    let folderName = URL(fileURLWithPath: trimPath).lastPathComponent
                    let marketplace = Marketplace(
                        id: UUID(),
                        name: name.isEmpty ? folderName : name,
                        owner: "Local",
                        description: nil,
                        vendor: localVendor,
                        url: trimPath,
                        ref: nil,
                        plugins: [],
                        lastFetched: nil,
                        fetchError: nil
                    )
                    onAdd(marketplace)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(localPath.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
    }

    // MARK: - Helpers

    /// Extracts "owner/repo" from a Git URL, stripping scheme, host prefix, and .git suffix.
    /// Works for both https://github.com/owner/repo and git@github.com:owner/repo.git.
    nonisolated static func extractOrgRepo(from url: String) -> String {
        // Normalise SSH colon separator: git@github.com:owner/repo → git@github.com/owner/repo
        let normalised = url.replacingOccurrences(of: ":", with: "/")
        let parts =
            normalised
            .components(separatedBy: "/")
            .map { $0.hasSuffix(".git") ? String($0.dropLast(4)) : $0 }
            .filter { !$0.isEmpty && !$0.hasPrefix("http") && !$0.contains("@") }
        guard parts.count >= 2 else { return parts.last ?? "" }
        return "\(parts[parts.count - 2])/\(parts[parts.count - 1])"
    }
}
