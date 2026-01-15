import Foundation
import MCP
import XCTest

@testable import MCPServerLib

final class InputValidatorTests: XCTestCase {

    // MARK: - String Validation Tests

    func testRequireStringSuccess() throws {
        let args: [String: Value] = ["name": .string("test")]
        let result = try InputValidator.requireString("name", from: args, tool: "test_tool")
        XCTAssertEqual(result, "test")
    }

    func testRequireStringMissing() {
        let args: [String: Value] = [:]

        XCTAssertThrowsError(try InputValidator.requireString("name", from: args, tool: "test_tool")) { error in
            guard let validationError = error as? InputValidator.ValidationError else {
                XCTFail("Expected ValidationError")
                return
            }
            if case .missingRequired(let param, let tool) = validationError {
                XCTAssertEqual(param, "name")
                XCTAssertEqual(tool, "test_tool")
            } else {
                XCTFail("Expected missingRequired error")
            }
        }
    }

    func testRequireStringWrongType() {
        let args: [String: Value] = ["name": .int(42)]

        XCTAssertThrowsError(try InputValidator.requireString("name", from: args, tool: "test_tool")) { error in
            guard let validationError = error as? InputValidator.ValidationError else {
                XCTFail("Expected ValidationError")
                return
            }
            if case .invalidType(let param, let expected, _) = validationError {
                XCTAssertEqual(param, "name")
                XCTAssertEqual(expected, "string")
            } else {
                XCTFail("Expected invalidType error")
            }
        }
    }

    func testRequireNonEmptyStringSuccess() throws {
        let args: [String: Value] = ["name": .string("test")]
        let result = try InputValidator.requireNonEmptyString("name", from: args, tool: "test_tool")
        XCTAssertEqual(result, "test")
    }

    func testRequireNonEmptyStringEmpty() {
        let args: [String: Value] = ["name": .string("")]

        XCTAssertThrowsError(try InputValidator.requireNonEmptyString("name", from: args, tool: "test_tool")) { error in
            guard let validationError = error as? InputValidator.ValidationError else {
                XCTFail("Expected ValidationError")
                return
            }
            if case .emptyValue(let param) = validationError {
                XCTAssertEqual(param, "name")
            } else {
                XCTFail("Expected emptyValue error")
            }
        }
    }

    func testOptionalStringPresent() {
        let args: [String: Value] = ["name": .string("test")]
        let result = InputValidator.optionalString("name", from: args)
        XCTAssertEqual(result, "test")
    }

    func testOptionalStringMissing() {
        let args: [String: Value] = [:]
        let result = InputValidator.optionalString("name", from: args)
        XCTAssertNil(result)
    }

    func testOptionalStringNil() {
        let result = InputValidator.optionalString("name", from: nil)
        XCTAssertNil(result)
    }

    // MARK: - Boolean Validation Tests

    func testOptionalBoolPresent() {
        let args: [String: Value] = ["flag": .bool(true)]
        let result = InputValidator.optionalBool("flag", from: args)
        XCTAssertTrue(result)
    }

    func testOptionalBoolMissing() {
        let args: [String: Value] = [:]
        let result = InputValidator.optionalBool("flag", from: args)
        XCTAssertFalse(result)
    }

    func testOptionalBoolWithDefault() {
        let args: [String: Value] = [:]
        let result = InputValidator.optionalBool("flag", from: args, default: true)
        XCTAssertTrue(result)
    }

    // MARK: - UUID Validation Tests

    func testRequireUUIDSuccess() throws {
        let uuid = UUID()
        let args: [String: Value] = ["id": .string(uuid.uuidString)]
        let result = try InputValidator.requireUUID("id", from: args, tool: "test_tool")
        XCTAssertEqual(result, uuid)
    }

    func testRequireUUIDInvalidFormat() {
        let args: [String: Value] = ["id": .string("not-a-uuid")]

        XCTAssertThrowsError(try InputValidator.requireUUID("id", from: args, tool: "test_tool")) { error in
            guard let validationError = error as? InputValidator.ValidationError else {
                XCTFail("Expected ValidationError")
                return
            }
            if case .invalidUUID(let param, let value) = validationError {
                XCTAssertEqual(param, "id")
                XCTAssertEqual(value, "not-a-uuid")
            } else {
                XCTFail("Expected invalidUUID error")
            }
        }
    }

    func testOptionalUUIDPresent() throws {
        let uuid = UUID()
        let args: [String: Value] = ["id": .string(uuid.uuidString)]
        let result = try InputValidator.optionalUUID("id", from: args)
        XCTAssertEqual(result, uuid)
    }

    func testOptionalUUIDMissing() throws {
        let args: [String: Value] = [:]
        let result = try InputValidator.optionalUUID("id", from: args)
        XCTAssertNil(result)
    }

    func testOptionalUUIDInvalidFormat() {
        let args: [String: Value] = ["id": .string("not-a-uuid")]

        XCTAssertThrowsError(try InputValidator.optionalUUID("id", from: args)) { error in
            guard case InputValidator.ValidationError.invalidUUID = error else {
                XCTFail("Expected invalidUUID error")
                return
            }
        }
    }

    // MARK: - Path Validation Tests

    func testValidatePathExpandsTilde() throws {
        let result = try InputValidator.validatePath("path", value: "~/test", mustExist: false)
        XCTAssertTrue(result.contains(NSHomeDirectory()))
        XCTAssertTrue(result.contains("test"))
    }

    func testValidatePathEmpty() {
        XCTAssertThrowsError(try InputValidator.validatePath("path", value: "", mustExist: false)) { error in
            guard case InputValidator.ValidationError.invalidPath(_, _, let reason) = error else {
                XCTFail("Expected invalidPath error")
                return
            }
            XCTAssertTrue(reason.contains("empty"))
        }
    }

    func testValidatePathMustExistSuccess() throws {
        // Use a path we know exists (strip trailing slash for consistent comparison)
        let tempDir = NSTemporaryDirectory().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let tempPath = "/" + tempDir
        let result = try InputValidator.validatePath("path", value: tempPath, mustExist: true)
        XCTAssertEqual(result, tempPath)
    }

    func testValidatePathMustExistFails() {
        XCTAssertThrowsError(
            try InputValidator.validatePath("path", value: "/nonexistent/path/12345", mustExist: true)
        ) { error in
            guard case InputValidator.ValidationError.invalidPath(_, _, let reason) = error else {
                XCTFail("Expected invalidPath error")
                return
            }
            XCTAssertTrue(reason.contains("does not exist"))
        }
    }

    func testOptionalPathPresent() throws {
        // Use a path we know exists (strip trailing slash for consistent comparison)
        let tempDir = NSTemporaryDirectory().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let tempPath = "/" + tempDir
        let args: [String: Value] = ["path": .string(tempPath)]
        let result = try InputValidator.optionalPath("path", from: args, mustExist: true)
        XCTAssertEqual(result, tempPath)
    }

    func testOptionalPathMissing() throws {
        let args: [String: Value] = [:]
        let result = try InputValidator.optionalPath("path", from: args)
        XCTAssertNil(result)
    }

    // MARK: - Error Description Tests

    func testValidationErrorDescriptions() {
        let errors: [InputValidator.ValidationError] = [
            .missingRequired(parameter: "name", tool: "test"),
            .invalidUUID(parameter: "id", value: "bad"),
            .invalidPath(parameter: "path", value: "/test", reason: "not found"),
            .invalidType(parameter: "count", expected: "int", got: "string"),
            .emptyValue(parameter: "title"),
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
}
