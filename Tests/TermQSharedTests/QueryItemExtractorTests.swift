import XCTest

@testable import TermQShared

final class QueryItemExtractorTests: XCTestCase {

    // MARK: - Helpers

    private func items(_ pairs: (String, String?)...) -> [URLQueryItem] {
        pairs.map { URLQueryItem(name: $0.0, value: $0.1) }
    }

    // MARK: - string()

    func testStringFound() {
        let extractor = QueryItemExtractor(items(("name", "My Terminal")))
        XCTAssertEqual(extractor.string("name"), "My Terminal")
    }

    func testStringMissingUsesEmptyDefault() {
        let extractor = QueryItemExtractor(items(("other", "value")))
        XCTAssertEqual(extractor.string("name"), "")
    }

    func testStringMissingUsesCustomDefault() {
        let extractor = QueryItemExtractor(items())
        XCTAssertEqual(extractor.string("path", default: "/Users/test"), "/Users/test")
    }

    func testStringNilValueUsesDefault() {
        let extractor = QueryItemExtractor(items(("name", nil)))
        XCTAssertEqual(extractor.string("name", default: "fallback"), "fallback")
    }

    // MARK: - optionalString()

    func testOptionalStringFound() {
        let extractor = QueryItemExtractor(items(("col", "Done")))
        XCTAssertEqual(extractor.optionalString("col"), "Done")
    }

    func testOptionalStringMissingReturnsNil() {
        let extractor = QueryItemExtractor(items(("other", "val")))
        XCTAssertNil(extractor.optionalString("col"))
    }

    func testOptionalStringNilValueReturnsNil() {
        let extractor = QueryItemExtractor(items(("col", nil)))
        XCTAssertNil(extractor.optionalString("col"))
    }

    // MARK: - uuid()

    func testUUIDValidString() {
        let id = UUID()
        let extractor = QueryItemExtractor(items(("id", id.uuidString)))
        XCTAssertEqual(extractor.uuid("id"), id)
    }

    func testUUIDInvalidStringReturnsNil() {
        let extractor = QueryItemExtractor(items(("id", "not-a-uuid")))
        XCTAssertNil(extractor.uuid("id"))
    }

    func testUUIDMissingReturnsNil() {
        let extractor = QueryItemExtractor(items())
        XCTAssertNil(extractor.uuid("id"))
    }

    // MARK: - bool()

    func testBoolTrueLiteral() {
        let extractor = QueryItemExtractor(items(("flag", "true")))
        XCTAssertTrue(extractor.bool("flag"))
    }

    func testBoolFalseLiteral() {
        let extractor = QueryItemExtractor(items(("flag", "false")))
        XCTAssertFalse(extractor.bool("flag"))
    }

    func testBoolOneIsTrue() {
        let extractor = QueryItemExtractor(items(("flag", "1")))
        XCTAssertTrue(extractor.bool("flag"))
    }

    func testBoolZeroIsFalse() {
        let extractor = QueryItemExtractor(items(("flag", "0")))
        XCTAssertFalse(extractor.bool("flag"))
    }

    func testBoolCaseInsensitive() {
        let extractor = QueryItemExtractor(items(("flag", "TRUE")))
        XCTAssertTrue(extractor.bool("flag"))
    }

    func testBoolMissingUsesDefault() {
        let extractor = QueryItemExtractor(items())
        XCTAssertTrue(extractor.bool("flag", default: true))
        XCTAssertFalse(extractor.bool("flag", default: false))
    }

    // MARK: - optionalBool()

    func testOptionalBoolPresentTrue() {
        let extractor = QueryItemExtractor(items(("favourite", "true")))
        XCTAssertEqual(extractor.optionalBool("favourite"), true)
    }

    func testOptionalBoolPresentFalse() {
        let extractor = QueryItemExtractor(items(("favourite", "false")))
        XCTAssertEqual(extractor.optionalBool("favourite"), false)
    }

    func testOptionalBoolMissingReturnsNil() {
        let extractor = QueryItemExtractor(items())
        XCTAssertNil(extractor.optionalBool("favourite"))
    }

    func testOptionalBoolInvalidValueReturnsNil() {
        let extractor = QueryItemExtractor(items(("favourite", "maybe")))
        XCTAssertNil(extractor.optionalBool("favourite"))
    }

    // MARK: - int()

    func testIntValid() {
        let extractor = QueryItemExtractor(items(("count", "42")))
        XCTAssertEqual(extractor.int("count"), 42)
    }

    func testIntInvalidUsesDefault() {
        let extractor = QueryItemExtractor(items(("count", "abc")))
        XCTAssertEqual(extractor.int("count", default: 5), 5)
    }

    func testIntMissingUsesDefault() {
        let extractor = QueryItemExtractor(items())
        XCTAssertEqual(extractor.int("count", default: 99), 99)
    }

    // MARK: - allValues()

    func testAllValuesMultipleItems() {
        let extractor = QueryItemExtractor(items(("tag", "env=prod"), ("tag", "team=platform")))
        let values = extractor.allValues("tag")
        XCTAssertEqual(values.count, 2)
        XCTAssertTrue(values.contains("env=prod"))
        XCTAssertTrue(values.contains("team=platform"))
    }

    func testAllValuesSingleItem() {
        let extractor = QueryItemExtractor(items(("tag", "env=dev")))
        XCTAssertEqual(extractor.allValues("tag"), ["env=dev"])
    }

    func testAllValuesNoneReturnsEmpty() {
        let extractor = QueryItemExtractor(items(("other", "val")))
        XCTAssertTrue(extractor.allValues("tag").isEmpty)
    }

    func testAllValuesTrimsWhitespace() {
        let extractor = QueryItemExtractor(items(("tag", "  env=prod  ")))
        XCTAssertEqual(extractor.allValues("tag"), ["env=prod"])
    }

    func testAllValuesFiltersEmpty() {
        let extractor = QueryItemExtractor(items(("tag", ""), ("tag", "env=prod")))
        XCTAssertEqual(extractor.allValues("tag"), ["env=prod"])
    }

    // MARK: - URLComponents init

    func testInitFromURLComponents() {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "name", value: "Test")]
        let extractor = QueryItemExtractor(components)
        XCTAssertEqual(extractor.string("name"), "Test")
    }

    func testInitFromURLComponentsWithNilQueryItems() {
        let components = URLComponents()
        let extractor = QueryItemExtractor(components)
        XCTAssertEqual(extractor.string("name", default: "default"), "default")
    }
}
