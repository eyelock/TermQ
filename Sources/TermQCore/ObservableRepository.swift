import Foundation

/// Observable wrapper for a registered git repository — used for SwiftUI bindings.
///
/// Mirrors `GitRepository` from TermQShared but uses `@Published` for SwiftUI observation.
/// The codebase uses `ObservableObject` + `@Published` throughout (Board, TerminalCard, etc.);
/// this type follows the same convention.
public class ObservableRepository: ObservableObject, Identifiable {
    public let id: UUID
    @Published public var name: String
    @Published public var path: String
    @Published public var worktreeBasePath: String?
    public let addedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        worktreeBasePath: String? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.worktreeBasePath = worktreeBasePath
        self.addedAt = addedAt
    }
}
