extension ToolsTabContent {
    /// The groups of tools this view shows: Settings spreads them over its
    /// Integrations, Git & Stacks and Harnesses sections.
    enum Part: CaseIterable {
        case status, mcp, cli, tmux, gh, stackProviders, ynh
    }
}
