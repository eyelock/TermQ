import Foundation
import MCP
import XCTest

@testable import MCPServerLib

final class SchemaBuilderTests: XCTestCase {
    // MARK: - Property Type Tests

    func testPropertyTypeRawValues() {
        XCTAssertEqual(SchemaBuilder.PropertyType.string.rawValue, "string")
        XCTAssertEqual(SchemaBuilder.PropertyType.boolean.rawValue, "boolean")
        XCTAssertEqual(SchemaBuilder.PropertyType.integer.rawValue, "integer")
        XCTAssertEqual(SchemaBuilder.PropertyType.number.rawValue, "number")
        XCTAssertEqual(SchemaBuilder.PropertyType.array.rawValue, "array")
        XCTAssertEqual(SchemaBuilder.PropertyType.object.rawValue, "object")
    }

    // MARK: - Property Creation Tests

    func testPropertyInitialization() {
        let prop = SchemaBuilder.Property("name", .string, description: "Test description", required: true)

        XCTAssertEqual(prop.name, "name")
        XCTAssertEqual(prop.type, .string)
        XCTAssertEqual(prop.description, "Test description")
        XCTAssertTrue(prop.isRequired)
    }

    func testPropertyInitializationOptional() {
        let prop = SchemaBuilder.Property("count", .integer, description: "A count", required: false)

        XCTAssertEqual(prop.name, "count")
        XCTAssertEqual(prop.type, .integer)
        XCTAssertFalse(prop.isRequired)
    }

    // MARK: - Convenience Method Tests

    func testStringPropertyCreation() {
        let prop = SchemaBuilder.string("name", "A name field", required: true)

        XCTAssertEqual(prop.name, "name")
        XCTAssertEqual(prop.type, .string)
        XCTAssertEqual(prop.description, "A name field")
        XCTAssertTrue(prop.isRequired)
    }

    func testStringPropertyOptional() {
        let prop = SchemaBuilder.string("name", "A name field")

        XCTAssertFalse(prop.isRequired)
    }

    func testBoolPropertyCreation() {
        let prop = SchemaBuilder.bool("enabled", "Whether enabled", required: true)

        XCTAssertEqual(prop.name, "enabled")
        XCTAssertEqual(prop.type, .boolean)
        XCTAssertEqual(prop.description, "Whether enabled")
        XCTAssertTrue(prop.isRequired)
    }

    func testBoolPropertyOptional() {
        let prop = SchemaBuilder.bool("enabled", "Whether enabled")

        XCTAssertFalse(prop.isRequired)
    }

    func testIntPropertyCreation() {
        let prop = SchemaBuilder.int("count", "Number of items", required: true)

        XCTAssertEqual(prop.name, "count")
        XCTAssertEqual(prop.type, .integer)
        XCTAssertEqual(prop.description, "Number of items")
        XCTAssertTrue(prop.isRequired)
    }

    func testIntPropertyOptional() {
        let prop = SchemaBuilder.int("count", "Number of items")

        XCTAssertFalse(prop.isRequired)
    }

    // MARK: - Object Schema Tests

    func testEmptySchema() {
        let schema = SchemaBuilder.emptySchema()

        guard case .object(let dict) = schema else {
            XCTFail("Expected object value")
            return
        }

        XCTAssertEqual(dict["type"]?.stringValue, "object")

        // Check properties is empty object
        guard case .object(let properties) = dict["properties"] else {
            XCTFail("Expected properties to be object")
            return
        }
        XCTAssertTrue(properties.isEmpty)

        // Check required is empty array
        guard case .array(let required) = dict["required"] else {
            XCTFail("Expected required to be array")
            return
        }
        XCTAssertTrue(required.isEmpty)
    }

    func testObjectSchemaWithSingleProperty() {
        let properties = [
            SchemaBuilder.string("name", "The name", required: true)
        ]
        let schema = SchemaBuilder.objectSchema(properties)

        guard case .object(let dict) = schema else {
            XCTFail("Expected object value")
            return
        }

        XCTAssertEqual(dict["type"]?.stringValue, "object")

        // Check properties contains "name"
        guard case .object(let props) = dict["properties"] else {
            XCTFail("Expected properties to be object")
            return
        }
        XCTAssertEqual(props.count, 1)
        XCTAssertNotNil(props["name"])

        // Check name property has correct type and description
        guard case .object(let nameProp) = props["name"] else {
            XCTFail("Expected name property to be object")
            return
        }
        XCTAssertEqual(nameProp["type"]?.stringValue, "string")
        XCTAssertEqual(nameProp["description"]?.stringValue, "The name")

        // Check required contains "name"
        guard case .array(let required) = dict["required"] else {
            XCTFail("Expected required to be array")
            return
        }
        XCTAssertEqual(required.count, 1)
        XCTAssertEqual(required[0].stringValue, "name")
    }

    func testObjectSchemaWithMultipleProperties() {
        let properties = [
            SchemaBuilder.string("name", "The name", required: true),
            SchemaBuilder.int("count", "Number of items", required: false),
            SchemaBuilder.bool("enabled", "Whether enabled", required: true),
        ]
        let schema = SchemaBuilder.objectSchema(properties)

        guard case .object(let dict) = schema else {
            XCTFail("Expected object value")
            return
        }

        // Check properties contains all 3
        guard case .object(let props) = dict["properties"] else {
            XCTFail("Expected properties to be object")
            return
        }
        XCTAssertEqual(props.count, 3)
        XCTAssertNotNil(props["name"])
        XCTAssertNotNil(props["count"])
        XCTAssertNotNil(props["enabled"])

        // Verify property types
        guard case .object(let nameProp) = props["name"] else {
            XCTFail("Expected name property to be object")
            return
        }
        XCTAssertEqual(nameProp["type"]?.stringValue, "string")

        guard case .object(let countProp) = props["count"] else {
            XCTFail("Expected count property to be object")
            return
        }
        XCTAssertEqual(countProp["type"]?.stringValue, "integer")

        guard case .object(let enabledProp) = props["enabled"] else {
            XCTFail("Expected enabled property to be object")
            return
        }
        XCTAssertEqual(enabledProp["type"]?.stringValue, "boolean")

        // Check required contains only required properties (name and enabled)
        guard case .array(let required) = dict["required"] else {
            XCTFail("Expected required to be array")
            return
        }
        XCTAssertEqual(required.count, 2)
        let requiredNames = required.compactMap { $0.stringValue }
        XCTAssertTrue(requiredNames.contains("name"))
        XCTAssertTrue(requiredNames.contains("enabled"))
        XCTAssertFalse(requiredNames.contains("count"))
    }

    func testObjectSchemaWithAllOptionalProperties() {
        let properties = [
            SchemaBuilder.string("name", "The name", required: false),
            SchemaBuilder.int("count", "Number of items", required: false),
        ]
        let schema = SchemaBuilder.objectSchema(properties)

        guard case .object(let dict) = schema else {
            XCTFail("Expected object value")
            return
        }

        // Check required is empty since all properties are optional
        guard case .array(let required) = dict["required"] else {
            XCTFail("Expected required to be array")
            return
        }
        XCTAssertTrue(required.isEmpty)
    }

    func testObjectSchemaWithArrayProperty() {
        let properties = [
            SchemaBuilder.Property("items", .array, description: "List of items", required: true)
        ]
        let schema = SchemaBuilder.objectSchema(properties)

        guard case .object(let dict) = schema else {
            XCTFail("Expected object value")
            return
        }

        guard case .object(let props) = dict["properties"] else {
            XCTFail("Expected properties to be object")
            return
        }

        guard case .object(let itemsProp) = props["items"] else {
            XCTFail("Expected items property to be object")
            return
        }
        XCTAssertEqual(itemsProp["type"]?.stringValue, "array")
    }

    func testObjectSchemaWithObjectProperty() {
        let properties = [
            SchemaBuilder.Property("config", .object, description: "Configuration object", required: false)
        ]
        let schema = SchemaBuilder.objectSchema(properties)

        guard case .object(let dict) = schema else {
            XCTFail("Expected object value")
            return
        }

        guard case .object(let props) = dict["properties"] else {
            XCTFail("Expected properties to be object")
            return
        }

        guard case .object(let configProp) = props["config"] else {
            XCTFail("Expected config property to be object")
            return
        }
        XCTAssertEqual(configProp["type"]?.stringValue, "object")
    }

    func testObjectSchemaWithNumberProperty() {
        let properties = [
            SchemaBuilder.Property("price", .number, description: "Price value", required: true)
        ]
        let schema = SchemaBuilder.objectSchema(properties)

        guard case .object(let dict) = schema else {
            XCTFail("Expected object value")
            return
        }

        guard case .object(let props) = dict["properties"] else {
            XCTFail("Expected properties to be object")
            return
        }

        guard case .object(let priceProp) = props["price"] else {
            XCTFail("Expected price property to be object")
            return
        }
        XCTAssertEqual(priceProp["type"]?.stringValue, "number")
    }
}
