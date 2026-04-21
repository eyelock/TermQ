import Foundation

/// Utility for escaping strings for safe use in POSIX shell contexts.
enum ShellEscaper {

    /// Wraps `value` in single quotes, escaping any embedded single quotes.
    /// Safe for use as a shell argument — prevents all variable and command expansion.
    /// Example: `hello 'world'` → `'hello '"'"'world'"'"''`
    static func singleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    /// Escapes `value` for embedding inside a double-quoted shell string.
    /// Escapes: `\` `"` `$` `` ` `` — prevents variable/command expansion while allowing
    /// the template to supply the surrounding quotes.
    static func doubleQuote(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
    }

    /// Converts `name` to a valid environment variable name fragment.
    /// - Converts to uppercase
    /// - Replaces any character that is not A–Z, 0–9, or `_` with `_`
    /// - Strips any leading digits or underscores
    static func envVarName(_ name: String) -> String {
        var result = name.uppercased().map { char -> Character in
            (char.isLetter || char.isNumber || char == "_") ? char : "_"
        }.reduce("") { String($0) + String($1) }

        while let first = result.first, first.isNumber || first == "_" {
            result.removeFirst()
        }

        return result
    }
}
