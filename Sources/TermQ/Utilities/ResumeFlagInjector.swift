import Foundation

/// Adds `--resume` to a `ynh run` init command at send time.
///
/// The flag is injected when the command is dispatched rather than stored on
/// the card, because `initCommand` is persisted and replayed on every open.
/// Baking the flag in would mean rewriting a stored — and possibly hand-edited
/// — command string every time the card's resume setting changed. Injecting
/// late keeps a single source of truth (`TerminalCard.autoResumeSession`) and
/// leaves whatever the user typed untouched on disk.
struct ResumeFlagInjector {
    static let flag = "--resume"

    /// Returns `command` with `--resume` inserted, or unchanged when it should
    /// not apply.
    ///
    /// Placement matters: `ynh run` takes a trailing prompt after a `--`
    /// separator, and anything appended past that separator becomes part of the
    /// prompt rather than a flag. The flag is therefore inserted immediately
    /// before the separator when one is present, and appended otherwise.
    func inject(into command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return command }

        // Already resuming — whether TermQ added it or the user typed it.
        // Matches "--resume" and "--resume=<id>"; an explicit id the user wrote
        // by hand always wins.
        if containsResumeFlag(trimmed) { return command }

        guard let separatorRange = promptSeparatorRange(in: trimmed) else {
            return trimmed + " " + Self.flag
        }

        let head = trimmed[trimmed.startIndex..<separatorRange.lowerBound]
            .trimmingCharacters(in: .whitespaces)
        let tail = trimmed[separatorRange.lowerBound...]
        return head + " " + Self.flag + " " + tail
    }

    /// Whether the command already carries a resume flag in any form.
    func containsResumeFlag(_ command: String) -> Bool {
        tokens(of: command).contains {
            $0 == Self.flag || $0.hasPrefix(Self.flag + "=")
        }
    }

    // MARK: - Internals

    /// Range of the ` -- ` prompt separator, if the command has one.
    ///
    /// Matched on token boundaries so a `--` inside a quoted prompt (or a
    /// flag that merely starts with `--`) is never mistaken for the separator.
    private func promptSeparatorRange(in command: String) -> Range<String.Index>? {
        var searchStart = command.startIndex
        while let range = command.range(of: "--", range: searchStart..<command.endIndex) {
            let precededBySpace =
                range.lowerBound == command.startIndex
                || command[command.index(before: range.lowerBound)] == " "
            let followedBySpaceOrEnd =
                range.upperBound == command.endIndex
                || command[range.upperBound] == " "

            if precededBySpace && followedBySpaceOrEnd {
                return range
            }
            searchStart = range.upperBound
        }
        return nil
    }

    /// Whitespace-split tokens, ignoring quoted regions so a `--resume`
    /// appearing inside a prompt string is not read as a flag.
    private func tokens(of command: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?

        for char in command {
            if let open = quote {
                if char == open { quote = nil } else { current.append(char) }
                continue
            }
            switch char {
            case "\"", "'":
                quote = char
            case " ", "\t":
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            default:
                current.append(char)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
