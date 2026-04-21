import Foundation
import TermQCore

// MARK: - Supporting Types

/// Represents a tmux pane in control mode
public struct TmuxPane: Identifiable, Sendable {
    public let id: String
    public var windowId: String
    public var width: Int
    public var height: Int
    public var x: Int
    public var y: Int
    public var title: String = ""
    public var currentPath: String = ""
    public var inCopyMode: Bool = false
    public var isActive: Bool = false

    public init(id: String, windowId: String, width: Int, height: Int, x: Int, y: Int) {
        self.id = id
        self.windowId = windowId
        self.width = width
        self.height = height
        self.x = x
        self.y = y
    }
}

/// Represents a tmux window in control mode
public struct TmuxWindow: Identifiable, Sendable {
    public let id: String
    public var name: String
    public var layout: String = ""
    public var isActive: Bool = false

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Response from a tmux control mode command
public struct CommandResponse: Sendable {
    public let id: Int
    public var output: String = ""
    public var isComplete: Bool = false

    public init(id: Int) {
        self.id = id
    }
}
