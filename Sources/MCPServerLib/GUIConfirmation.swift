import Foundation
import TermQShared

/// Confirmation predicates for board mutations routed through the GUI's URL scheme.
///
/// Opening a `termq://` URL is fire-and-forget: `NSWorkspace.open` reports only that the URL
/// was dispatched, and the app silently drops anything it cannot apply. A GUI-routed mutation
/// is therefore not known to have happened until it is visible on the board, so every GUI path
/// must confirm against `board.json` rather than assume the command was honoured.
public enum GUIConfirmation {

    // MARK: - Column Resolution

    /// Resolve a column by name, case-insensitively.
    ///
    /// Deliberately matches `BoardWriter.moveCard` and the app's URL handler — name only, never
    /// id. Keeping all three in step is what makes the GUI and headless paths agree on which
    /// column names are valid, so the same request cannot succeed on one and fail on the other.
    public static func column(named name: String, in board: Board) -> Column? {
        let wanted = name.lowercased()
        return board.columns.first { $0.name.lowercased() == wanted }
    }

    /// Column names in board order, for error messages that tell the caller what is valid.
    public static func columnNames(in board: Board) -> [String] {
        board.sortedColumns().map(\.name)
    }

    // MARK: - Confirmation Predicates

    /// True once `cardId` sits in `column`.
    public static func cardIsInColumn(_ board: Board, cardId: String, column: String) -> Bool {
        guard let card = board.findTerminal(identifier: cardId) else { return false }
        return board.columnName(for: card.columnId).lowercased() == column.lowercased()
    }

    /// True once `cardId` has left the active board — soft-deleted to the bin, or purged.
    public static func cardIsAbsent(_ board: Board, cardId: String) -> Bool {
        board.findTerminal(identifier: cardId) == nil
    }

    /// True once every observable field of an update has landed on `cardId`.
    public static func cardMatches(_ board: Board, cardId: String, expected: ExpectedUpdate) -> Bool {
        guard let card = board.findTerminal(identifier: cardId) else { return false }

        if let title = expected.title, card.title != title { return false }
        if let description = expected.description, card.description != description { return false }
        if let badge = expected.badge, card.badge != badge { return false }
        if let llmPrompt = expected.llmPrompt, card.llmPrompt != llmPrompt { return false }
        if let llmNextAction = expected.llmNextAction, card.llmNextAction != llmNextAction { return false }
        if let isFavourite = expected.isFavourite, card.isFavourite != isFavourite { return false }
        if let column = expected.column, !cardIsInColumn(board, cardId: cardId, column: column) { return false }

        let present = Set(card.tags.map(TagIdentity.init))
        if let exact = expected.exactTags, present != Set(exact.map(TagIdentity.init)) { return false }
        if let required = expected.requiredTags,
            !Set(required.map(TagIdentity.init)).isSubset(of: present)
        {
            return false
        }

        return true
    }

    /// The observable half of a `set` request.
    ///
    /// `board.json` does not persist everything `set` accepts — `initCommand` is applied to the
    /// live card and never written to disk — so confirmation can only assert the fields that
    /// actually land. A nil field was not requested and is not checked.
    public struct ExpectedUpdate: Sendable, Equatable {
        public var title: String?
        public var description: String?
        public var badge: String?
        public var llmPrompt: String?
        public var llmNextAction: String?
        public var isFavourite: Bool?
        public var column: String?
        /// Tags the request added; each must be present afterwards.
        public var requiredTags: [Tag]?
        /// Set when the request replaced the tag list wholesale — the card must carry exactly these.
        public var exactTags: [Tag]?

        public init(
            title: String? = nil,
            description: String? = nil,
            badge: String? = nil,
            llmPrompt: String? = nil,
            llmNextAction: String? = nil,
            isFavourite: Bool? = nil,
            column: String? = nil,
            requiredTags: [Tag]? = nil,
            exactTags: [Tag]? = nil
        ) {
            self.title = title
            self.description = description
            self.badge = badge
            self.llmPrompt = llmPrompt
            self.llmNextAction = llmNextAction
            self.isFavourite = isFavourite
            self.column = column
            self.requiredTags = requiredTags
            self.exactTags = exactTags
        }

        /// Whether this request changes anything the board records.
        ///
        /// When false the card's continued existence is the only thing confirmation can assert,
        /// so callers fall back to a presence check rather than reporting a spurious failure.
        public var hasObservableFields: Bool {
            title != nil || description != nil || badge != nil || llmPrompt != nil
                || llmNextAction != nil || isFavourite != nil || column != nil
                || requiredTags != nil || exactTags != nil
        }
    }

    /// `Tag` mints a fresh `id` per instance, so identity has to rest on the pair that carries
    /// the meaning — otherwise a tag that did land would never compare equal to the one requested.
    private struct TagIdentity: Hashable {
        let key: String
        let value: String

        init(_ tag: Tag) {
            key = tag.key
            value = tag.value
        }
    }
}
