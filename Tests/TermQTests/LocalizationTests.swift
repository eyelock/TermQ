import Foundation
import XCTest

/// Tests for localization functionality
/// These tests verify that .strings files can be parsed correctly and contain expected translations
final class LocalizationTests: XCTestCase {

    // MARK: - Parser Tests

    /// Parse a .strings file into a dictionary, handling comments
    /// This is a copy of the parser in Strings.swift for testing purposes
    private func parseStringsFile(at url: URL) -> [String: String]? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        var result: [String: String] = [:]

        // Remove block comments
        var cleanContent = content
        while let startRange = cleanContent.range(of: "/*"),
            let endRange = cleanContent.range(of: "*/", range: startRange.upperBound..<cleanContent.endIndex)
        {
            cleanContent.removeSubrange(startRange.lowerBound...endRange.upperBound)
        }

        for line in cleanContent.components(separatedBy: .newlines) {
            var line = line

            // Remove line comments
            if let commentRange = line.range(of: "//") {
                line = String(line[..<commentRange.lowerBound])
            }

            line = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            guard !line.isEmpty, line.hasPrefix("\"") else { continue }

            // Find first quoted string (key)
            guard let keyStart = line.firstIndex(of: "\"") else { continue }
            let afterKeyStart = line.index(after: keyStart)
            guard afterKeyStart < line.endIndex,
                let keyEnd = line[afterKeyStart...].firstIndex(of: "\"")
            else { continue }

            let key = String(line[afterKeyStart..<keyEnd])

            // Find "=" and value
            let afterKey = line.index(after: keyEnd)
            guard afterKey < line.endIndex,
                let equalsRange = line[afterKey...].range(of: "="),
                let valueStart = line[equalsRange.upperBound...].firstIndex(of: "\"")
            else { continue }

            // Find end of value (handle escaped quotes)
            let afterValueStart = line.index(after: valueStart)
            guard afterValueStart < line.endIndex else { continue }

            var valueEnd: String.Index?
            var idx = afterValueStart
            while idx < line.endIndex {
                if line[idx] == "\"" {
                    // Check if escaped
                    let prevIdx = line.index(before: idx)
                    if prevIdx >= afterValueStart && line[prevIdx] == "\\" {
                        idx = line.index(after: idx)
                        continue
                    }
                    valueEnd = idx
                    break
                }
                idx = line.index(after: idx)
            }

            guard let valueEnd = valueEnd else { continue }
            var value = String(line[afterValueStart..<valueEnd])

            // Unescape common sequences
            value = value.replacingOccurrences(of: "\\\"", with: "\"")
            value = value.replacingOccurrences(of: "\\n", with: "\n")
            value = value.replacingOccurrences(of: "\\\\", with: "\\")

            result[key] = value
        }

        return result.isEmpty ? nil : result
    }

    /// Get the path to a localization file
    private func localizationFileURL(for languageCode: String) -> URL? {
        // Try multiple approaches to find the Resources directory

        // Approach 1: Relative to current working directory (works in Xcode and command line)
        let cwd = FileManager.default.currentDirectoryPath
        let cwdPath = URL(fileURLWithPath: cwd)
            .appendingPathComponent("Sources/TermQ/Resources/\(languageCode).lproj/Localizable.strings")
        if FileManager.default.fileExists(atPath: cwdPath.path) {
            return cwdPath
        }

        // Approach 2: Look for the package root by finding Package.swift
        var searchPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let packageSwift = searchPath.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: packageSwift.path) {
                let resourcePath = searchPath
                    .appendingPathComponent("Sources/TermQ/Resources/\(languageCode).lproj/Localizable.strings")
                if FileManager.default.fileExists(atPath: resourcePath.path) {
                    return resourcePath
                }
            }
            searchPath = searchPath.deletingLastPathComponent()
        }

        return nil
    }

    // MARK: - English Localization Tests

    func testEnglishStringsFileExists() {
        let url = localizationFileURL(for: "en")
        XCTAssertNotNil(url, "English localization file should exist")
    }

    func testEnglishStringsCanBeParsed() {
        guard let url = localizationFileURL(for: "en") else {
            XCTFail("English localization file not found")
            return
        }

        let dict = parseStringsFile(at: url)
        XCTAssertNotNil(dict, "English strings file should be parseable")
        XCTAssertGreaterThan(dict?.count ?? 0, 200, "English should have 200+ localization keys")
    }

    func testEnglishContainsRequiredKeys() {
        guard let url = localizationFileURL(for: "en"),
            let dict = parseStringsFile(at: url)
        else {
            XCTFail("Could not parse English localization file")
            return
        }

        // Test critical UI keys exist
        let requiredKeys = [
            "app.name",
            "common.ok",
            "common.cancel",
            "settings.tab.general",
            "settings.tab.tools",
            "settings.tab.data",
            "board.column.add.terminal",
        ]

        for key in requiredKeys {
            XCTAssertNotNil(dict[key], "English should contain key: \(key)")
        }
    }

    // MARK: - Non-English Localization Tests (Regression Prevention)

    func testDanishStringsFileExists() {
        let url = localizationFileURL(for: "da")
        XCTAssertNotNil(url, "Danish localization file should exist")
    }

    func testDanishStringsCanBeParsed() {
        guard let url = localizationFileURL(for: "da") else {
            XCTFail("Danish localization file not found")
            return
        }

        let dict = parseStringsFile(at: url)
        XCTAssertNotNil(dict, "Danish strings file should be parseable")
        XCTAssertGreaterThan(dict?.count ?? 0, 200, "Danish should have 200+ localization keys")
    }

    func testDanishContainsTranslatedValues() {
        guard let url = localizationFileURL(for: "da"),
            let dict = parseStringsFile(at: url)
        else {
            XCTFail("Could not parse Danish localization file")
            return
        }

        // These are the keys that were showing as untranslated in the bug
        XCTAssertEqual(dict["settings.tab.general"], "Generelt", "Danish translation for settings.tab.general")
        XCTAssertEqual(dict["settings.tab.tools"], "Værktøjer", "Danish translation for settings.tab.tools")
        XCTAssertEqual(dict["settings.tab.data"], "Data", "Danish translation for settings.tab.data")
        XCTAssertEqual(dict["board.column.add.terminal"], "Tilføj terminal", "Danish translation for board.column.add.terminal")
    }

    func testDanishTranslationsDifferFromEnglish() {
        guard let enURL = localizationFileURL(for: "en"),
            let daURL = localizationFileURL(for: "da"),
            let enDict = parseStringsFile(at: enURL),
            let daDict = parseStringsFile(at: daURL)
        else {
            XCTFail("Could not parse localization files")
            return
        }

        // Verify Danish translations are actually different from English
        // (catches copy-paste errors or missing translations)
        let keysToCheck = ["common.cancel", "common.save", "settings.tab.general"]

        for key in keysToCheck {
            guard let enValue = enDict[key], let daValue = daDict[key] else {
                XCTFail("Key \(key) missing from one of the files")
                continue
            }
            XCTAssertNotEqual(enValue, daValue, "Danish translation for '\(key)' should differ from English")
        }
    }

    // MARK: - All Languages Validation

    func testAllLanguageFilesAreParseable() {
        let languageCodes = [
            "en", "en-GB", "en-AU",
            "da", "de", "es", "fr", "it", "nl", "pt", "sv",
            "ja", "ko", "zh-Hans", "zh-Hant",
            "ar", "he", "ru", "pl", "cs",
        ]

        for code in languageCodes {
            guard let url = localizationFileURL(for: code) else {
                // Some codes might not exist, that's okay
                continue
            }

            let dict = parseStringsFile(at: url)
            XCTAssertNotNil(dict, "\(code) strings file should be parseable")
            XCTAssertGreaterThan(
                dict?.count ?? 0, 100,
                "\(code) should have 100+ keys (found \(dict?.count ?? 0))"
            )
        }
    }

    // MARK: - Parser Edge Cases

    func testParserHandlesBlockComments() {
        let content = """
            /* This is a block comment */
            "key1" = "value1";
            /* Multi
               line
               comment */
            "key2" = "value2";
            """

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.strings")
        try? content.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let dict = parseStringsFile(at: tempURL)
        XCTAssertEqual(dict?["key1"], "value1")
        XCTAssertEqual(dict?["key2"], "value2")
    }

    func testParserHandlesLineComments() {
        let content = """
            // This is a line comment
            "key1" = "value1";
            "key2" = "value2"; // inline comment
            """

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.strings")
        try? content.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let dict = parseStringsFile(at: tempURL)
        XCTAssertEqual(dict?["key1"], "value1")
        XCTAssertEqual(dict?["key2"], "value2")
    }

    func testParserHandlesEscapedCharacters() {
        let content = """
            "key1" = "value with \\"quotes\\"";
            "key2" = "line1\\nline2";
            "key3" = "back\\\\slash";
            """

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.strings")
        try? content.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let dict = parseStringsFile(at: tempURL)
        XCTAssertEqual(dict?["key1"], "value with \"quotes\"")
        XCTAssertEqual(dict?["key2"], "line1\nline2")
        XCTAssertEqual(dict?["key3"], "back\\slash")
    }

    func testParserHandlesEmptyLines() {
        let content = """
            "key1" = "value1";

            "key2" = "value2";


            "key3" = "value3";
            """

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.strings")
        try? content.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let dict = parseStringsFile(at: tempURL)
        XCTAssertEqual(dict?.count, 3)
    }
}
