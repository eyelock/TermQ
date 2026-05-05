import Foundation

struct YNHMarketplace: Identifiable, Decodable {
    var id: String { url }
    let url: String
    let name: String
    let description: String?
    let ref: String?
}

@MainActor
final class YNHMarketplaceService: ObservableObject {
    @Published private(set) var marketplaces: [YNHMarketplace] = []
    @Published private(set) var isLoading = false

    private let commandRunner: any YNHCommandRunner

    init(commandRunner: any YNHCommandRunner = LiveYNHCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func refresh(ynhPath: String, environment: [String: String]) async {
        isLoading = true
        defer { isLoading = false }
        if let data = await fetch(
            executable: ynhPath, args: ["registry", "list", "--format", "json"], environment: environment),
            let decoded = try? JSONDecoder().decode([YNHMarketplace].self, from: data)
        {
            marketplaces = decoded
        }
    }

    func remove(url: String, ynhPath: String, environment: [String: String]) async {
        await runSilent(executable: ynhPath, args: ["registry", "remove", url], environment: environment)
        await refresh(ynhPath: ynhPath, environment: environment)
    }

    private func fetch(executable: String, args: [String], environment: [String: String]) async -> Data? {
        guard
            let result = try? await commandRunner.run(
                executable: executable,
                arguments: args,
                environment: environment
            ),
            result.didSucceed
        else { return nil }
        return Data(result.stdout.utf8)
    }

    private func runSilent(executable: String, args: [String], environment: [String: String]) async {
        _ = try? await commandRunner.run(
            executable: executable,
            arguments: args,
            environment: environment
        )
    }
}
