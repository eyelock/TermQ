import Foundation
import XCTest

@testable import TermQCore

final class ColumnTests: XCTestCase {
    func testInitializationWithDefaults() {
        let column = Column(name: "Test Column", orderIndex: 0)

        XCTAssertEqual(column.name, "Test Column")
        XCTAssertEqual(column.orderIndex, 0)
        XCTAssertEqual(column.color, "#6B7280")  // Default gray
    }

    func testInitializationWithCustomColor() {
        let column = Column(
            name: "Custom",
            orderIndex: 1,
            color: "#FF0000"
        )

        XCTAssertEqual(column.name, "Custom")
        XCTAssertEqual(column.orderIndex, 1)
        XCTAssertEqual(column.color, "#FF0000")
    }

    func testDefaultColumns() {
        let defaults = Column.defaults

        XCTAssertEqual(defaults.count, 4)
        XCTAssertEqual(defaults[0].name, "To Do")
        XCTAssertEqual(defaults[1].name, "In Progress")
        XCTAssertEqual(defaults[2].name, "Blocked")
        XCTAssertEqual(defaults[3].name, "Done")

        // Check order indices
        for (index, column) in defaults.enumerated() {
            XCTAssertEqual(column.orderIndex, index)
        }
    }

    func testCodableRoundTrip() throws {
        let original = Column(
            name: "Encoded Column",
            orderIndex: 5,
            color: "#123456"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Column.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.orderIndex, original.orderIndex)
        XCTAssertEqual(decoded.color, original.color)
    }

    func testEquatableConformance() {
        let id = UUID()
        let column1 = Column(id: id, name: "A", orderIndex: 0)
        let column2 = Column(id: id, name: "B", orderIndex: 1)  // Same ID, different properties

        XCTAssertEqual(column1, column2)  // Equal by ID

        let column3 = Column(name: "A", orderIndex: 0)
        XCTAssertNotEqual(column1, column3)  // Different IDs
    }

    func testObservableProperties() {
        let column = Column(name: "Observable", orderIndex: 0)

        column.name = "Updated"
        column.orderIndex = 10
        column.color = "#ABCDEF"

        XCTAssertEqual(column.name, "Updated")
        XCTAssertEqual(column.orderIndex, 10)
        XCTAssertEqual(column.color, "#ABCDEF")
    }

    // MARK: - Backwards Compatibility Tests

    func testDecodeWithoutDescriptionField() throws {
        // JSON without description field - should default to empty string
        let id = UUID()
        let json = """
            {
                "id": "\(id.uuidString)",
                "name": "Test Column",
                "orderIndex": 2,
                "color": "#FF0000"
            }
            """

        let decoded = try JSONDecoder().decode(Column.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.name, "Test Column")
        XCTAssertEqual(decoded.description, "")  // Should default to empty
        XCTAssertEqual(decoded.orderIndex, 2)
        XCTAssertEqual(decoded.color, "#FF0000")
    }

    func testDecodeWithDescriptionField() throws {
        // JSON with description field
        let id = UUID()
        let json = """
            {
                "id": "\(id.uuidString)",
                "name": "Test Column",
                "description": "A test description",
                "orderIndex": 1,
                "color": "#00FF00"
            }
            """

        let decoded = try JSONDecoder().decode(Column.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.name, "Test Column")
        XCTAssertEqual(decoded.description, "A test description")
        XCTAssertEqual(decoded.orderIndex, 1)
        XCTAssertEqual(decoded.color, "#00FF00")
    }

    func testInitializationWithDescription() {
        let column = Column(
            name: "Test",
            description: "My description",
            orderIndex: 0
        )

        XCTAssertEqual(column.description, "My description")
    }

    func testDescriptionPublishedProperty() {
        let column = Column(name: "Test", orderIndex: 0)

        XCTAssertEqual(column.description, "")

        column.description = "Updated description"
        XCTAssertEqual(column.description, "Updated description")
    }
}
