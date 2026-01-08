import Foundation
import XCTest

@testable import TermQCore

final class TagTests: XCTestCase {
    func testInitializationWithDefaultId() {
        let tag = Tag(key: "environment", value: "production")

        XCTAssertEqual(tag.key, "environment")
        XCTAssertEqual(tag.value, "production")
    }

    func testInitializationWithCustomId() {
        let customId = UUID()
        let tag = Tag(id: customId, key: "version", value: "1.0.0")

        XCTAssertEqual(tag.id, customId)
        XCTAssertEqual(tag.key, "version")
        XCTAssertEqual(tag.value, "1.0.0")
    }

    func testCodableRoundTrip() throws {
        let original = Tag(key: "project", value: "termq")

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Tag.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.key, original.key)
        XCTAssertEqual(decoded.value, original.value)
    }

    func testHashableConformance() {
        let tag1 = Tag(key: "env", value: "dev")
        let tag2 = Tag(key: "env", value: "dev")

        // Different IDs mean different hash values
        XCTAssertNotEqual(tag1.hashValue, tag2.hashValue)

        // Same tag should have consistent hash
        XCTAssertEqual(tag1.hashValue, tag1.hashValue)
    }

    func testTagInSet() {
        let tag1 = Tag(key: "a", value: "1")
        let tag2 = Tag(key: "b", value: "2")

        var tagSet: Set<Tag> = []
        tagSet.insert(tag1)
        tagSet.insert(tag2)

        XCTAssertEqual(tagSet.count, 2)
        XCTAssertTrue(tagSet.contains(tag1))
        XCTAssertTrue(tagSet.contains(tag2))
    }
}
