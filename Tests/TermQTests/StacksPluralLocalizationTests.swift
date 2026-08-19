import Foundation
import XCTest

/// Guards the `.stringsdict` files that give the stack sheets correct plural
/// agreement.
///
/// The bug these exist to prevent was visible in the Link sheet: "Creates 1 new
/// pull requests on GitHub." — a count of 1 is the *common* case there, since a
/// stack usually has a single branch without a pull request yet.
///
/// What these tests can and cannot prove:
///
/// - Structure, key parity and placeholder sanity are checked directly.
/// - `one` vs `other` selection is exercised through a real `Bundle`.
/// - `few` / `two` / `many` selection is NOT exercised. Foundation picks the
///   plural rules from the running localization, and a test process cannot
///   adopt one, so Polish forms would be selected by English rules here and the
///   assertion would be meaningless. Those forms are covered structurally only.
final class StacksPluralLocalizationTests: XCTestCase {

    /// The keys that carry a count into a stack sheet.
    private let pluralKeys = [
        "stacks.merge.stack.message %ld",
        "stacks.merge.stack.confirm %ld",
        "stacks.link.stack.will.create %ld",
        "stacks.link.stack.confirm %ld",
        "stacks.checkout.stack %ld",
        "stacks.checkout.stack.done %ld",
    ]

    // MARK: - Structure

    func testEveryStringsdictIsAWellFormedPluralDictionary() throws {
        let dicts = try allStringsdicts()
        XCTAssertFalse(dicts.isEmpty, "no .stringsdict files found — check the resource path")

        for (language, entries) in dicts {
            for (key, raw) in entries {
                let entry = try XCTUnwrap(
                    raw as? [String: Any], "\(language): \(key) is not a dictionary")
                XCTAssertEqual(
                    entry["NSStringLocalizedFormatKey"] as? String, "%#@count@",
                    "\(language): \(key) has an unexpected format key")

                let variable = try XCTUnwrap(
                    entry["count"] as? [String: Any], "\(language): \(key) has no 'count' variable")
                XCTAssertEqual(
                    variable["NSStringFormatSpecTypeKey"] as? String, "NSStringPluralRuleType",
                    "\(language): \(key) is not declared as a plural rule")
                XCTAssertEqual(
                    variable["NSStringFormatValueTypeKey"] as? String, "ld",
                    "\(language): \(key) must format a long, matching the %ld in the key")

                // `other` is the only category Foundation is guaranteed to fall back
                // to. Without it a count in an unlisted category renders as nothing.
                XCTAssertNotNil(
                    variable["other"] as? String,
                    "\(language): \(key) is missing the required 'other' form")
            }
        }
    }

    /// Every plural key must ALSO exist in the language's `.strings`. The two files
    /// are separate resources: if the `.stringsdict` is ever dropped from the bundle,
    /// a key that lives only there renders as the raw key in the UI.
    func testEveryPluralKeyAlsoExistsInTheStringsFile() throws {
        for (language, entries) in try allStringsdicts() {
            let strings = try XCTUnwrap(
                stringsFileKeys(for: language), "\(language): could not read Localizable.strings")
            for key in entries.keys {
                XCTAssertTrue(
                    strings.contains(key),
                    "\(language): \(key) is in .stringsdict but missing from .strings, "
                        + "so it would render as the raw key if the dictionary were dropped")
            }
        }
    }

    /// A plural form takes the count at most once and never a different specifier.
    /// A stray `%@` here crashes at format time rather than rendering wrongly.
    func testPluralFormsCarryOnlyTheCountPlaceholder() throws {
        for (language, entries) in try allStringsdicts() {
            for (key, raw) in entries {
                guard let entry = raw as? [String: Any],
                    let variable = entry["count"] as? [String: Any]
                else { continue }
                for (category, form) in variable {
                    guard let form = form as? String,
                        !category.hasPrefix("NSString")
                    else { continue }
                    let specifiers = form.components(separatedBy: "%").count - 1
                    XCTAssertLessThanOrEqual(
                        specifiers, 1,
                        "\(language): \(key)/\(category) has more than one placeholder: \(form)")
                    XCTAssertFalse(
                        form.contains("%@"),
                        "\(language): \(key)/\(category) uses %@ where the count is a number")
                }
            }
        }
    }

    // MARK: - Behaviour

    /// The regression itself: 1 must not read as a plural.
    func testEnglishSelectsTheSingularForOneAndThePluralForMore() throws {
        let lproj = try XCTUnwrap(lprojURL(for: "en"))
        let bundle = try XCTUnwrap(
            Bundle(path: lproj.path), "could not open en.lproj as a bundle")

        for key in pluralKeys {
            let format = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
            XCTAssertNotEqual(format, key, "\(key) did not resolve at all")

            let one = String(format: format, 1)
            let many = String(format: format, 3)
            XCTAssertNotEqual(
                one, many,
                "\(key) renders identically for 1 and 3 — the plural forms are not being selected")
            XCTAssertFalse(
                one.contains("pull requests") || one.contains("branches") || one.contains("PRs"),
                "\(key) still reads as a plural at a count of 1: \(one)")
        }
    }

    // MARK: - Helpers

    /// language code -> parsed .stringsdict contents, for every language that has one.
    private func allStringsdicts() throws -> [String: [String: Any]] {
        let root = try XCTUnwrap(resourcesURL(), "could not locate Sources/TermQ/Resources")
        var result: [String: [String: Any]] = [:]
        for entry in try FileManager.default.contentsOfDirectory(atPath: root.path)
        where entry.hasSuffix(".lproj") {
            let url = root.appendingPathComponent(entry)
                .appendingPathComponent("Localizable.stringsdict")
            guard let data = try? Data(contentsOf: url) else { continue }
            let plist = try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil)
            result[String(entry.dropLast(6))] = try XCTUnwrap(
                plist as? [String: Any], "\(entry): .stringsdict is not a dictionary")
        }
        return result
    }

    private func stringsFileKeys(for language: String) throws -> Set<String>? {
        guard let url = lprojURL(for: language)?.appendingPathComponent("Localizable.strings"),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        var keys: Set<String> = []
        for line in contents.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("\""), let close = line.dropFirst().firstIndex(of: "\"") else {
                continue
            }
            keys.insert(String(line[line.index(after: line.startIndex)..<close]))
        }
        return keys
    }

    private func lprojURL(for language: String) -> URL? {
        resourcesURL()?.appendingPathComponent("\(language).lproj")
    }

    /// Walk up from the working directory to the checked-in resources. Reading the
    /// source tree rather than the built bundle keeps these tests honest about what
    /// is committed.
    private func resourcesURL() -> URL? {
        var search = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let candidate =
                search
                .appendingPathComponent("Sources")
                .appendingPathComponent("TermQ")
                .appendingPathComponent("Resources")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            search = search.deletingLastPathComponent()
        }
        return nil
    }
}
