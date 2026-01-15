import Foundation
import TermQShared

// MARK: - Type Aliases for API Compatibility

// Re-export shared types with MCP prefix for backwards compatibility with existing code
public typealias MCPTag = Tag
public typealias MCPColumn = Column
public typealias MCPCard = Card
public typealias MCPBoard = Board

// Re-export BoardLoader and BoardWriter from TermQShared
// (No aliases needed, they're exported directly)
