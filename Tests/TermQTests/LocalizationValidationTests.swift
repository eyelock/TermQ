import Foundation
import XCTest

@testable import TermQCore

/// Critical validation tests for all localization files
/// These tests MUST pass before any build is allowed - broken localization files
/// break the entire app's localization system, causing all strings to show as keys.
final class LocalizationValidationTests: XCTestCase {

    // MARK: - Test Data

    /// All supported language codes (40 languages)
    private let allLanguages = [
        "ar", "ca", "cs", "da", "de", "el",
        "en-AU", "en-GB", "en",
        "es-419", "es",
        "fi", "fr-CA", "fr", "he", "hi", "hr", "hu",
        "id", "it", "ja", "ko", "ms",
        "nl", "no", "pl", "pt-PT", "pt", "ro", "ru",
        "sk", "sl", "sv", "th", "tr", "uk", "vi",
        "zh-Hans", "zh-Hant", "zh-HK"
    ]

    // MARK: - Validation Tests

    /// Test that NO localization file has duplicate keys
    /// CRITICAL: Duplicate keys cause undefined behavior - last key wins, but macOS may reject file
    func testNoLocalizationFileHasDuplicateKeys() throws {
        var filesWithDuplicates: [String: [String]] = [:]

        for languageCode in allLanguages {
            let duplicates = findDuplicateKeys(languageCode: languageCode)

            if !duplicates.isEmpty {
                filesWithDuplicates[languageCode] = duplicates
            }
        }

        // Assert NO files have duplicates
        XCTAssertTrue(
            filesWithDuplicates.isEmpty,
            """
            \(filesWithDuplicates.count) localization files have DUPLICATE KEYS:
            \(filesWithDuplicates.map { lang, keys in
                "  - \(lang): \(keys.joined(separator: ", "))"
            }.joined(separator: "\n"))

            This causes undefined behavior and may break localization.
            Remove duplicate keys.
            """
        )
    }

    /// Test that all strings files can be loaded by PropertyListSerialization
    /// CRITICAL: If macOS can't parse the file, localization breaks entirely
    func testAllStringsFilesCanBeLoadedBySystem() throws {
        var failedFiles: [String: String] = [:]

        for languageCode in allLanguages {
            guard let url = localizableStringsURL(for: languageCode) else {
                failedFiles[languageCode] = "File not found"
                continue
            }

            do {
                let data = try Data(contentsOf: url)
                // Try to parse as property list (what macOS does internally)
                _ = try PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as? [String: String]
            } catch {
                failedFiles[languageCode] = error.localizedDescription
            }
        }

        // Assert ALL files can be loaded
        XCTAssertTrue(
            failedFiles.isEmpty,
            """
            \(failedFiles.count) localization files CANNOT BE LOADED by macOS:
            \(failedFiles.map { "  - \($0.key): \($0.value)" }.joined(separator: "\n"))

            These files will cause localization to fail completely.
            Fix the file format.
            """
        )
    }

    /// Test that English localization has no missing keys
    /// CRITICAL: English is the base language - all other languages reference it
    func testEnglishLocalizationIsComplete() throws {
        guard let englishDict = loadStringsFile(languageCode: "en") else {
            XCTFail("Cannot load English localization - this is CRITICAL")
            return
        }

        // English should have at least 200 keys (rough sanity check)
        XCTAssertGreaterThan(
            englishDict.count,
            200,
            "English localization appears incomplete (only \(englishDict.count) keys)"
        )

        // Check for specific critical keys
        let criticalKeys = [
            "app.name",
            "board.column.add.terminal",
            "common.ok",
            "common.cancel"
        ]

        for key in criticalKeys {
            XCTAssertNotNil(
                englishDict[key],
                "English localization is missing CRITICAL key: \(key)"
            )
        }
    }

    // MARK: - Helper Methods

    /// Finds duplicate keys in a .strings file
    private func findDuplicateKeys(languageCode: String) -> [String] {
        guard let dict = loadStringsFile(languageCode: languageCode) else {
            return []
        }

        guard let url = localizableStringsURL(for: languageCode),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        var keyCounts: [String: Int] = [:]

        // Parse file line by line to count key occurrences
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") {
                continue
            }

            // Extract key from "key" = "value";
            if let firstQuote = trimmed.firstIndex(of: "\""),
               let secondQuote = trimmed[trimmed.index(after: firstQuote)...].firstIndex(of: "\"") {
                let key = String(trimmed[trimmed.index(after: firstQuote)..<secondQuote])
                keyCounts[key, default: 0] += 1
            }
        }

        // Return keys that appear more than once
        return keyCounts.filter { $0.value > 1 }.map { $0.key }.sorted()
    }

    /// Loads a .strings file into a dictionary
    private func loadStringsFile(languageCode: String) -> [String: String]? {
        guard let url = localizableStringsURL(for: languageCode) else {
            return nil
        }

        guard let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: String] else {
            return nil
        }

        return dict
    }

    /// Gets the URL for a Localizable.strings file
    private func localizableStringsURL(for languageCode: String) -> URL? {
        // Try to find the file in the test bundle or main bundle
        let bundle = Bundle(for: type(of: self))

        // First try the resource bundle (TermQ_TermQ.bundle)
        if let resourceBundleURL = bundle.resourceURL?.appendingPathComponent("TermQ_TermQ.bundle"),
           let resourceBundle = Bundle(url: resourceBundleURL),
           let url = resourceBundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: "\(languageCode).lproj") {
            return url
        }

        // Fall back to checking the source directory (for tests run without building the bundle)
        let fileManager = FileManager.default
        let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)

        // Try going up from .build/debug to find Sources
        var searchURL = currentDirectoryURL
        for _ in 0..<5 {
            let sourcesURL = searchURL
                .appendingPathComponent("Sources")
                .appendingPathComponent("TermQ")
                .appendingPathComponent("Resources")
                .appendingPathComponent("\(languageCode).lproj")
                .appendingPathComponent("Localizable.strings")

            if fileManager.fileExists(atPath: sourcesURL.path) {
                return sourcesURL
            }

            searchURL = searchURL.deletingLastPathComponent()
        }

        return nil
    }
}
