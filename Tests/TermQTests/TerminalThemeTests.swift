import AppKit
import XCTest

@testable import TermQ

final class TerminalThemeTests: XCTestCase {

    // MARK: - NSColor.hex() failable initializer

    func testHexWithHash_parsesCorrectly() {
        XCTAssertNotNil(NSColor(hex: "#FFFFFF"))
    }

    func testHexWithoutHash_parsesCorrectly() {
        XCTAssertNotNil(NSColor(hex: "FFFFFF"))
    }

    func testRedHex_hasCorrectComponents() {
        let color = NSColor(hex: "#FF0000")
        let rgb = color?.usingColorSpace(.deviceRGB)
        XCTAssertNotNil(rgb)
        XCTAssertEqual(rgb!.redComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(rgb!.greenComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(rgb!.blueComponent, 0.0, accuracy: 0.01)
    }

    func testBlackHex_allComponentsZero() {
        let color = NSColor(hex: "#000000")
        let rgb = color?.usingColorSpace(.deviceRGB)
        XCTAssertNotNil(rgb)
        XCTAssertEqual(rgb!.redComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(rgb!.greenComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(rgb!.blueComponent, 0.0, accuracy: 0.01)
    }

    func testWhiteHex_allComponentsOne() {
        let color = NSColor(hex: "#FFFFFF")
        let rgb = color?.usingColorSpace(.deviceRGB)
        XCTAssertNotNil(rgb)
        XCTAssertEqual(rgb!.redComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(rgb!.greenComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(rgb!.blueComponent, 1.0, accuracy: 0.01)
    }

    func testInvalidHex_initializerReturnsNil() {
        XCTAssertNil(NSColor(hex: "ZZZZZZ"))
        XCTAssertNil(NSColor(hex: ""))
        XCTAssertNil(NSColor(hex: "#XYZ"))
    }

    func testHexNonfailable_validInput_returnsColor() {
        let color = NSColor.hex("#282A36")
        let rgb = color.usingColorSpace(.deviceRGB)
        XCTAssertNotNil(rgb)
    }

    func testLowercaseHex_parsesCorrectly() {
        XCTAssertNotNil(NSColor(hex: "#ff0000"))
    }

    func testMixedCaseHex_parsesCorrectly() {
        XCTAssertNotNil(NSColor(hex: "#Ff0000"))
    }

    // MARK: - TerminalTheme.theme(for:)

    func testThemeForKnownId_returnsCorrectTheme() {
        let theme = TerminalTheme.theme(for: "dracula")
        XCTAssertEqual(theme.id, "dracula")
        XCTAssertEqual(theme.name, "Dracula")
    }

    func testThemeForUnknownId_returnsDefaultDark() {
        let theme = TerminalTheme.theme(for: "nonexistent-theme-id")
        XCTAssertEqual(theme.id, "default-dark")
    }

    func testThemeForEmptyString_returnsDefaultDark() {
        let theme = TerminalTheme.theme(for: "")
        XCTAssertEqual(theme.id, "default-dark")
    }

    // MARK: - allThemes collection

    func testAllThemes_haveDistinctIds() {
        let ids = TerminalTheme.allThemes.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testAllThemes_haveNonEmptyNames() {
        for theme in TerminalTheme.allThemes {
            XCTAssertFalse(theme.name.isEmpty, "\(theme.id) has empty name")
        }
    }

    func testAllThemes_haveNonEmptyIds() {
        for theme in TerminalTheme.allThemes {
            XCTAssertFalse(theme.id.isEmpty)
        }
    }

    func testAllThemes_containsBuiltIns() {
        let ids = Set(TerminalTheme.allThemes.map(\.id))
        XCTAssertTrue(ids.contains("default-dark"))
        XCTAssertTrue(ids.contains("dracula"))
        XCTAssertTrue(ids.contains("one-dark"))
        XCTAssertTrue(ids.contains("nord"))
        XCTAssertTrue(ids.contains("solarized-dark"))
        XCTAssertTrue(ids.contains("solarized-light"))
        XCTAssertTrue(ids.contains("github-dark"))
        XCTAssertTrue(ids.contains("monokai"))
    }

    // MARK: - Theme integrity — each theme must have 16 ANSI colors

    func testAllThemes_haveSixteenAnsiColors() {
        for theme in TerminalTheme.allThemes {
            XCTAssertEqual(
                theme.ansiColors.count, 16,
                "\(theme.id) should have 16 ANSI colors, got \(theme.ansiColors.count)")
        }
    }

    func testAllThemes_swiftTermColorsMatchAnsiCount() {
        for theme in TerminalTheme.allThemes {
            XCTAssertEqual(
                theme.swiftTermColors.count, theme.ansiColors.count,
                "\(theme.id) swiftTermColors count mismatch")
        }
    }

    // MARK: - Equality

    func testSameId_equal() {
        let a = TerminalTheme.theme(for: "dracula")
        let b = TerminalTheme.theme(for: "dracula")
        XCTAssertEqual(a, b)
    }

    func testDifferentId_notEqual() {
        let a = TerminalTheme.theme(for: "dracula")
        let b = TerminalTheme.theme(for: "nord")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Static themes spot-checks

    func testDefaultDark_backgroundIsBlack() {
        let bg = TerminalTheme.defaultDark.background.usingColorSpace(.deviceRGB)
        XCTAssertNotNil(bg)
        XCTAssertEqual(bg!.redComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(bg!.greenComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(bg!.blueComponent, 0.0, accuracy: 0.01)
    }

    func testDracula_backgroundIsCorrectHex() {
        // #282A36
        let bg = TerminalTheme.dracula.background.usingColorSpace(.deviceRGB)
        XCTAssertNotNil(bg)
        XCTAssertEqual(bg!.redComponent, CGFloat(0x28) / 255.0, accuracy: 0.01)
        XCTAssertEqual(bg!.greenComponent, CGFloat(0x2A) / 255.0, accuracy: 0.01)
        XCTAssertEqual(bg!.blueComponent, CGFloat(0x36) / 255.0, accuracy: 0.01)
    }
}
