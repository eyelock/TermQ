import TermQShared

@MainActor
protocol RepoPersistenceProtocol: AnyObject {
    func loadConfig() -> RepoConfig
    func save(_ config: RepoConfig) throws
    func startFileMonitoring(onExternalChange: @escaping @Sendable () -> Void)
}
