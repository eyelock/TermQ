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

    func testValidatePathIsFile() throws {
        // Create a temporary file (not a directory)
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-TestFile-\(UUID().uuidString).txt")
        try "test".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        XCTAssertThrowsError(
            try InputValidator.validatePath("path", value: tempFile.path, mustExist: true)
        ) { error in
            guard case InputValidator.ValidationError.invalidPath(_, _, let reason) = error else {
                XCTFail("Expected invalidPath error")
                return
            }
            XCTAssertTrue(reason.contains("not a directory"))
        }
    }

    func testOptionalPathDoesNotExist() {
        let args: [String: Value] = ["path": .string("/nonexistent/path/12345")]

        XCTAssertThrowsError(try InputValidator.optionalPath("path", from: args, mustExist: true)) { error in
            guard case InputValidator.ValidationError.invalidPath(_, _, let reason) = error else {
                XCTFail("Expected invalidPath error")
                return
            }
            XCTAssertTrue(reason.contains("does not exist"))
        }
    }

    func testOptionalPathWithoutExistCheck() throws {
        let args: [String: Value] = ["path": .string("/nonexistent/path/12345")]
        let result = try InputValidator.optionalPath("path", from: args, mustExist: false)
        XCTAssertEqual(result, "/nonexistent/path/12345")
    }

    // MARK: - Boolean Edge Cases

    func testOptionalBoolFalseValue() {
        let args: [String: Value] = ["flag": .bool(false)]
        let result = InputValidator.optionalBool("flag", from: args)
        XCTAssertFalse(result)
    }

    func testOptionalBoolNilArguments() {
        let result = InputValidator.optionalBool("flag", from: nil)
        XCTAssertFalse(result)
    }

    func testOptionalBoolNilArgumentsWithDefault() {
        let result = InputValidator.optionalBool("flag", from: nil, default: true)
        XCTAssertTrue(result)
    }

    // MARK: - Type Validation Edge Cases

    func testRequireStringWithNullValue() {
        let args: [String: Value] = ["name": .null]

        XCTAssertThrowsError(try InputValidator.requireString("name", from: args, tool: "test_tool")) { error in
            guard let validationError = error as? InputValidator.ValidationError else {
                XCTFail("Expected ValidationError")
                return
            }
            if case .invalidType(let param, let expected, let got) = validationError {
                XCTAssertEqual(param, "name")
                XCTAssertEqual(expected, "string")
                XCTAssertEqual(got, "null")
            } else {
                XCTFail("Expected invalidType error")
            }
        }
    }

    func testRequireStringWithBoolValue() {
        let args: [String: Value] = ["name": .bool(true)]

        XCTAssertThrowsError(try InputValidator.requireString("name", from: args, tool: "test_tool")) { error in
            guard let validationError = error as? InputValidator.ValidationError else {
                XCTFail("Expected ValidationError")
                return
            }
            if case .invalidType(let param, let expected, let got) = validationError {
                XCTAssertEqual(param, "name")
                XCTAssertEqual(expected, "string")
                XCTAssertEqual(got, "boolean")
            } else {
                XCTFail("Expected invalidType error")
            }
        }
    }

    func testRequireStringWithDoubleValue() {
        let args: [String: Value] = ["name": .double(3.14)]

        XCTAssertThrowsError(try InputValidator.requireString("name", from: args, tool: "test_tool")) { error in
            guard let validationError = error as? InputValidator.ValidationError else {
                XCTFail("Expected ValidationError")
                return
            }
            if case .invalidType(let param, let expected, let got) = validationError {
                XCTAssertEqual(param, "name")
                XCTAssertEqual(expected, "string")
                XCTAssertEqual(got, "number")
            } else {
                XCTFail("Expected invalidType error")
            }
        }
    }

    func testRequireStringWithArrayValue() {
        let args: [String: Value] = ["name": .array([.string("a"), .string("b")])]

        XCTAssertThrowsError(try InputValidator.requireString("name", from: args, tool: "test_tool")) { error in
            guard let validationError = error as? InputValidator.ValidationError else {
                XCTFail("Expected ValidationError")
                return
            }
            if case .invalidType(let param, let expected, let got) = validationError {
                XCTAssertEqual(param, "name")
                XCTAssertEqual(expected, "string")
                XCTAssertEqual(got, "array")
            } else {
                XCTFail("Expected invalidType error")
            }
        }
    }

    func testRequireStringWithObjectValue() {
        let args: [String: Value] = ["name": .object(["key": .string("value")])]

        XCTAssertThrowsError(try InputValidator.requireString("name", from: args, tool: "test_tool")) { error in
            guard let validationError = error as? InputValidator.ValidationError else {
                XCTFail("Expected ValidationError")
                return
            }
            if case .invalidType(let param, let expected, let got) = validationError {
                XCTAssertEqual(param, "name")
                XCTAssertEqual(expected, "string")
                XCTAssertEqual(got, "object")
            } else {
                XCTFail("Expected invalidType error")
            }
        }
    }

    func testRequireStringWithDataValue() {
        let args: [String: Value] = ["name": .data(Data([0x01, 0x02, 0x03]))]

        XCTAssertThrowsError(try InputValidator.requireString("name", from: args, tool: "test_tool")) { error in
            guard let validationError = error as? InputValidator.ValidationError else {
                XCTFail("Expected ValidationError")
                return
            }
            if case .invalidType(let param, let expected, let got) = validationError {
                XCTAssertEqual(param, "name")
                XCTAssertEqual(expected, "string")
                XCTAssertEqual(got, "data")
            } else {
                XCTFail("Expected invalidType error")
            }
        }
    }

    // MARK: - Nil Arguments Tests

    func testRequireStringFromNilArguments() {
        XCTAssertThrowsError(try InputValidator.requireString("name", from: nil, tool: "test_tool")) { error in
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

    func testOptionalUUIDFromNilArguments() throws {
        let result = try InputValidator.optionalUUID("id", from: nil)
        XCTAssertNil(result)
    }

    func testOptionalPathFromNilArguments() throws {
        let result = try InputValidator.optionalPath("path", from: nil)
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
            .valueTooLong(parameter: "content", maxLength: 100, actualLength: 150),
            .pathTraversal(parameter: "path", value: "../etc/passwd"),
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    // MARK: - Length Validation Tests

    func testValidateLengthSuccess() throws {
        let result = try InputValidator.validateLength("name", value: "short string", maxLength: 100)
        XCTAssertEqual(result, "short string")
    }

    func testValidateLengthExactLimit() throws {
        let value = String(repeating: "a", count: 100)
        let result = try InputValidator.validateLength("name", value: value, maxLength: 100)
        XCTAssertEqual(result, value)
    }

    func testValidateLengthExceedsLimit() {
        let value = String(repeating: "a", count: 101)

        XCTAssertThrowsError(try InputValidator.validateLength("name", value: value, maxLength: 100)) { error in
            guard let validationError = error as? InputValidator.ValidationError else {
                XCTFail("Expected ValidationError")
                return
            }
            if case .valueTooLong(let param, let maxLength, let actualLength) = validationError {
                XCTAssertEqual(param, "name")
                XCTAssertEqual(maxLength, 100)
                XCTAssertEqual(actualLength, 101)
            } else {
                XCTFail("Expected valueTooLong error")
            }
        }
    }

    // MARK: - Bounded String Tests

    func testOptionalBoundedStringSuccess() throws {
        let args: [String: Value] = ["name": .string("test value")]
        let result = try InputValidator.optionalBoundedString("name", from: args, maxLength: 100)
        XCTAssertEqual(result, "test value")
    }

    func testOptionalBoundedStringMissing() throws {
        let args: [String: Value] = [:]
        let result = try InputValidator.optionalBoundedString("name", from: args)
        XCTAssertNil(result)
    }

    func testOptionalBoundedStringNil() throws {
        let result = try InputValidator.optionalBoundedString("name", from: nil)
        XCTAssertNil(result)
    }

    func testOptionalBoundedStringExceedsLimit() {
        let longValue = String(repeating: "x", count: 1001)
        let args: [String: Value] = ["name": .string(longValue)]

        XCTAssertThrowsError(
            try InputValidator.optionalBoundedString("name", from: args, maxLength: 1000)
        ) { error in
            guard case InputValidator.ValidationError.valueTooLong(_, let max, let actual) = error else {
                XCTFail("Expected valueTooLong error")
                return
            }
            XCTAssertEqual(max, 1000)
            XCTAssertEqual(actual, 1001)
        }
    }

    func testOptionalBoundedStringUsesDefaultLimit() {
        // Test that default limit of maxGeneralStringLength (1000) is used
        let longValue = String(repeating: "x", count: 1001)
        let args: [String: Value] = ["name": .string(longValue)]

        XCTAssertThrowsError(try InputValidator.optionalBoundedString("name", from: args)) { error in
            guard case InputValidator.ValidationError.valueTooLong(_, let max, _) = error else {
                XCTFail("Expected valueTooLong error")
                return
            }
            XCTAssertEqual(max, InputValidator.maxGeneralStringLength)
        }
    }

    // MARK: - LLM Context Tests

    func testOptionalLLMContextSuccess() throws {
        let args: [String: Value] = ["llmPrompt": .string("This is a prompt for the LLM")]
        let result = try InputValidator.optionalLLMContext("llmPrompt", from: args)
        XCTAssertEqual(result, "This is a prompt for the LLM")
    }

    func testOptionalLLMContextMissing() throws {
        let args: [String: Value] = [:]
        let result = try InputValidator.optionalLLMContext("llmPrompt", from: args)
        XCTAssertNil(result)
    }

    func testOptionalLLMContextNil() throws {
        let result = try InputValidator.optionalLLMContext("llmPrompt", from: nil)
        XCTAssertNil(result)
    }

    func testOptionalLLMContextExceedsLimit() {
        let longValue = String(repeating: "x", count: 50001)
        let args: [String: Value] = ["llmPrompt": .string(longValue)]

        XCTAssertThrowsError(try InputValidator.optionalLLMContext("llmPrompt", from: args)) { error in
            guard case InputValidator.ValidationError.valueTooLong(_, let max, let actual) = error else {
                XCTFail("Expected valueTooLong error")
                return
            }
            XCTAssertEqual(max, InputValidator.maxLLMContextLength)
            XCTAssertEqual(actual, 50001)
        }
    }

    func testOptionalLLMContextAllowsLargeValues() throws {
        // LLM context allows up to 50000 chars
        let largeValue = String(repeating: "x", count: 50000)
        let args: [String: Value] = ["llmPrompt": .string(largeValue)]
        let result = try InputValidator.optionalLLMContext("llmPrompt", from: args)
        XCTAssertEqual(result?.count, 50000)
    }

    // MARK: - Path Traversal Prevention Tests

    func testValidatePathBlocksTraversalDotDot() {
        XCTAssertThrowsError(try InputValidator.validatePath("path", value: "../etc/passwd")) { error in
            guard case InputValidator.ValidationError.pathTraversal(let param, let value) = error else {
                XCTFail("Expected pathTraversal error")
                return
            }
            XCTAssertEqual(param, "path")
            XCTAssertEqual(value, "../etc/passwd")
        }
    }

    func testValidatePathBlocksTraversalMidPath() {
        XCTAssertThrowsError(
            try InputValidator.validatePath("path", value: "/Users/test/../../../etc/passwd")
        ) { error in
            guard case InputValidator.ValidationError.pathTraversal = error else {
                XCTFail("Expected pathTraversal error")
                return
            }
        }
    }

    func testValidatePathBlocksTraversalInMiddle() {
        XCTAssertThrowsError(
            try InputValidator.validatePath("path", value: "/home/user/../admin/secret")
        ) { error in
            guard case InputValidator.ValidationError.pathTraversal = error else {
                XCTFail("Expected pathTraversal error")
                return
            }
        }
    }

    func testValidatePathAllowsSingleDot() throws {
        // Single dots are fine (current directory)
        let result = try InputValidator.validatePath("path", value: "/Users/test/./project", mustExist: false)
        XCTAssertFalse(result.contains(".."))
    }

    func testValidatePathAllowsDoubleDotInFilename() throws {
        // Double dots in filename (not as path component) should be allowed
        let result = try InputValidator.validatePath("path", value: "/Users/test/file..txt", mustExist: false)
        XCTAssertTrue(result.contains("file..txt"))
    }

    // MARK: - Path Length Limit Tests

    func testValidatePathExceedsLengthLimit() {
        let longPath = "/" + String(repeating: "a", count: 4097)

        XCTAssertThrowsError(try InputValidator.validatePath("path", value: longPath)) { error in
            guard case InputValidator.ValidationError.valueTooLong(_, let max, _) = error else {
                XCTFail("Expected valueTooLong error")
                return
            }
            XCTAssertEqual(max, InputValidator.maxPathLength)
        }
    }

    func testValidatePathAtExactLimit() throws {
        let pathAtLimit = "/" + String(repeating: "a", count: 4095)
        XCTAssertEqual(pathAtLimit.count, 4096)

        // Should not throw for path at exact limit
        let result = try InputValidator.validatePath("path", value: pathAtLimit, mustExist: false)
        XCTAssertNotNil(result)
    }

    // MARK: - Security Limits Constants Tests

    func testSecurityLimitsAreReasonable() {
        // Verify the security limits are set to expected values
        XCTAssertEqual(InputValidator.maxGeneralStringLength, 1000)
        XCTAssertEqual(InputValidator.maxLLMContextLength, 50000)
        XCTAssertEqual(InputValidator.maxPathLength, 4096)
    }
}
