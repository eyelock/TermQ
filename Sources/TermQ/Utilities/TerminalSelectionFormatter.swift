import Foundation

/// Reformats text copied from a terminal selection for paste-ready use on a
/// shell command line. TUIs and agent output frequently render commands wrapped
/// across lines or with a uniform left indent — both break the command when
/// pasted into a shell. These transforms produce the literal text the user meant
/// to run.
enum TerminalSelectionFormatter {
    /// Collapse a multi-line selection into a single line: every line is trimmed
    /// of surrounding whitespace, blank lines are dropped, and the rest are joined
    /// with single spaces. Use when a TUI wrapped one logical command across rows.
    static func collapsingLineBreaks(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Remove the leading indentation shared by every non-blank line, preserving
    /// line breaks. Only the common outer indent is stripped, so relative
    /// indentation within the block (nested YAML, a heredoc body, an `if`/`fi`
    /// block) is kept intact. Returns the text unchanged when the lines share no
    /// leading whitespace.
    static func strippingIndentation(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")

        // Longest leading-whitespace prefix common to all non-blank lines.
        // Blank (empty or whitespace-only) lines never constrain the prefix.
        var common: String?
        for line in lines {
            guard let firstNonSpace = line.firstIndex(where: { $0 != " " && $0 != "\t" }) else {
                continue
            }
            let indent = String(line[line.startIndex..<firstNonSpace])
            common = common.map { $0.commonPrefix(with: indent) } ?? indent
            if common?.isEmpty == true { break }
        }

        guard let prefix = common, !prefix.isEmpty else { return text }

        let stripped = lines.map { line -> String in
            line.hasPrefix(prefix)
                ? String(line.dropFirst(prefix.count))
                : String(line.drop(while: { $0 == " " || $0 == "\t" }))
        }
        return stripped.joined(separator: "\n")
    }
}
