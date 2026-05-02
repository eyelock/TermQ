import SwiftUI

extension ContentView {
    func forkHarness(name: String) {
        harnessNameToFork = name
        showForkSheet = true
    }

    @ViewBuilder
    func harnessDetailView() -> some View {
        if let harness = harnessRepo.selectedHarness {
            let vm = HarnessDetailViewModel(
                harness: harness,
                detail: harnessRepo.selectedDetail,
                isLoadingDetail: harnessRepo.isLoadingDetail,
                detailError: harnessRepo.detailError,
                updateAvailability: updateAvailabilityService,
                capabilities: harnessRepo.lastCapabilities
            )
            HarnessDetailView(
                viewModel: vm,
                onDismiss: {
                    harnessRepo.selectedHarnessName = nil
                    if let card = cardBeforeHarness {
                        viewModel.selectCard(card)
                        cardBeforeHarness = nil
                    }
                },
                onLaunch: { path in
                    launchWorkingDirectory = path
                    Task { await vendorService.refresh() }
                    showLaunchSheet = true
                },
                onUpdate: { name in updateHarness(name: name) },
                onUninstall: { name in uninstallHarness(name: name) },
                onFork: { name in forkHarness(name: name) },
                onExport: { name, dir in exportHarness(name: name, outputDir: dir) }
            )
        }
    }

    @ViewBuilder
    func updateSheet(for name: String) -> some View {
        UpdateHarnessSheet(
            harnessName: name,
            detector: ynhDetector,
            repository: harnessRepo
        )
    }

    @ViewBuilder
    func forkSheet(for name: String) -> some View {
        if let harness = harnessRepo.harnesses.first(where: { $0.name == name }) {
            ForkHarnessSheet(
                harness: harness,
                detector: ynhDetector,
                repository: harnessRepo,
                onForkCompleted: { newName in
                    showForkSheet = false
                    harnessNameToFork = nil
                    harnessRepo.selectedHarnessName = newName
                }
            )
        }
    }
}
