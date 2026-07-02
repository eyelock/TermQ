import SwiftUI

/// Harness install/uninstall/export/fork/update/publish sheets, extracted
/// from `ContentView.body` to keep the struct body under the
/// `type_body_length` lint threshold.
struct HarnessLifecycleSheets: ViewModifier {
    @Bindable var lifecycleCoordinator: HarnessLifecycleCoordinator
    @ObservedObject var harnessRepo: HarnessRepository
    let ynhDetector: YNHDetector
    let forkSheet: (String) -> AnyView
    let updateSheet: (String) -> AnyView
    let publishSheetContent: () -> AnyView

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $lifecycleCoordinator.showInstallSheet) {
                HarnessInstallSheet(
                    installedNames: Set(harnessRepo.harnesses.map(\.name)),
                    harnesses: harnessRepo.harnesses
                ) { config in
                    lifecycleCoordinator.installHarness(config)
                }
                .frame(width: 520, height: 540)
            }
            .sheet(isPresented: $lifecycleCoordinator.showInstallProgressSheet) {
                Group {
                    if let config = lifecycleCoordinator.harnessConfigToInstall {
                        HarnessInstallProgressSheet(
                            config: config,
                            detector: ynhDetector,
                            repository: harnessRepo
                        )
                    }
                }
                .frame(width: 560, height: 420)
            }
            .sheet(isPresented: $lifecycleCoordinator.showUninstallSheet) {
                Group {
                    if let id = lifecycleCoordinator.harnessIDToUninstall {
                        let displayName =
                            harnessRepo.harnesses.first(where: { $0.id == id })?.name ?? id
                        HarnessUninstallSheet(
                            canonicalID: id,
                            harnessName: displayName,
                            detector: ynhDetector,
                            repository: harnessRepo
                        )
                    }
                }
                .frame(width: 560, height: 420)
            }
            .sheet(isPresented: $lifecycleCoordinator.showExportSheet) {
                Group {
                    if let pending = lifecycleCoordinator.pendingExport {
                        HarnessExportSheet(
                            harnessName: pending.harnessName,
                            harnessPath: pending.harnessPath,
                            outputDir: pending.outputDir,
                            detector: ynhDetector
                        )
                    }
                }
                .frame(width: 560, height: 420)
            }
            .sheet(isPresented: $lifecycleCoordinator.showForkSheet) {
                // Frame applied at the .sheet content closure (the absolute
                // outermost view NSWindow sees) so the window has a definitive
                // intrinsic size at first paint. Frame inside the sheet view's
                // body races against SwiftUI's layout pass and produces a
                // small placeholder until resolved.
                Group {
                    if let id = lifecycleCoordinator.harnessIDToFork {
                        forkSheet(id)
                    }
                }
                .frame(width: 560, height: 420)
            }
            .sheet(isPresented: $lifecycleCoordinator.showUpdateSheet) {
                Group {
                    if let id = lifecycleCoordinator.harnessIDToUpdate {
                        updateSheet(id)
                    }
                }
                .frame(width: 560, height: 420)
            }
            .sheet(isPresented: $lifecycleCoordinator.showPublishSheet) {
                publishSheetContent()
            }
    }
}
