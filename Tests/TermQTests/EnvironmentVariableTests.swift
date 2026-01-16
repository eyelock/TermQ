import XCTest

@testable import TermQCore

final class EnvironmentVariableTests: XCTestCase {
    // MARK: - Initialization Tests

    func testInitializationWithDefaults() {
        let variable = EnvironmentVariable(key: "TEST_KEY", value: "test_value", isSecret: false)

        XCTAssertFalse(variable.id.uuidString.isEmpty)
        XCTAssertEqual(variable.key, "TEST_KEY")
        XCTAssertEqual(variable.value, "test_value")
        XCTAssertFalse(variable.isSecret)
    }

    func testInitializationWithSecret() {
        let variable = EnvironmentVariable(key: "API_KEY", value: "secret123", isSecret: true)

        XCTAssertEqual(variable.key, "API_KEY")
        XCTAssertEqual(variable.value, "secret123")
        XCTAssertTrue(variable.isSecret)
    }

    func testInitializationWithCustomId() {
        let customId = UUID()
        let variable = EnvironmentVariable(
            id: customId, key: "CUSTOM", value: "value", isSecret: false)

        XCTAssertEqual(variable.id, customId)
    }

    // MARK: - Key Validation Tests

    func testValidKeySimple() {
        let variable = EnvironmentVariable(key: "VALID_KEY", value: "", isSecret: false)
        XCTAssertTrue(variable.isValidKey)
    }

    func testValidKeyWithNumbers() {
        let variable = EnvironmentVariable(key: "KEY_123", value: "", isSecret: false)
        XCTAssertTrue(variable.isValidKey)
    }

    func testValidKeyStartsWithUnderscore() {
        let variable = EnvironmentVariable(key: "_PRIVATE", value: "", isSecret: false)
        XCTAssertTrue(variable.isValidKey)
    }

    func testInvalidKeyEmpty() {
        let variable = EnvironmentVariable(key: "", value: "", isSecret: false)
        XCTAssertFalse(variable.isValidKey)
    }

    func testInvalidKeyStartsWithNumber() {
        let variable = EnvironmentVariable(key: "123_KEY", value: "", isSecret: false)
        XCTAssertFalse(variable.isValidKey)
    }

    func testInvalidKeyWithSpaces() {
        let variable = EnvironmentVariable(key: "KEY WITH SPACES", value: "", isSecret: false)
        XCTAssertFalse(variable.isValidKey)
    }

    func testInvalidKeyWithSpecialChars() {
        let variable = EnvironmentVariable(key: "KEY-NAME", value: "", isSecret: false)
        XCTAssertFalse(variable.isValidKey)
    }

    func testInvalidKeyWithEquals() {
        let variable = EnvironmentVariable(key: "KEY=VALUE", value: "", isSecret: false)
        XCTAssertFalse(variable.isValidKey)
    }

    // MARK: - Reserved Key Tests

    func testReservedKeyPath() {
        let variable = EnvironmentVariable(key: "PATH", value: "", isSecret: false)
        XCTAssertTrue(variable.isReservedKey)
    }

    func testReservedKeyHome() {
        let variable = EnvironmentVariable(key: "HOME", value: "", isSecret: false)
        XCTAssertTrue(variable.isReservedKey)
    }

    func testReservedKeyShell() {
        let variable = EnvironmentVariable(key: "SHELL", value: "", isSecret: false)
        XCTAssertTrue(variable.isReservedKey)
    }

    func testReservedKeyUser() {
        let variable = EnvironmentVariable(key: "USER", value: "", isSecret: false)
        XCTAssertTrue(variable.isReservedKey)
    }

    func testReservedKeyTerm() {
        let variable = EnvironmentVariable(key: "TERM", value: "", isSecret: false)
        XCTAssertTrue(variable.isReservedKey)
    }

    func testReservedKeyLang() {
        let variable = EnvironmentVariable(key: "LANG", value: "", isSecret: false)
        XCTAssertTrue(variable.isReservedKey)
    }

    func testNonReservedKey() {
        let variable = EnvironmentVariable(key: "MY_CUSTOM_VAR", value: "", isSecret: false)
        XCTAssertFalse(variable.isReservedKey)
    }

    func testReservedKeyCaseInsensitive() {
        let variable = EnvironmentVariable(key: "path", value: "", isSecret: false)
        XCTAssertTrue(variable.isReservedKey)
    }

    // MARK: - Codable Tests

    func testCodableRoundTrip() throws {
        let original = EnvironmentVariable(key: "TEST", value: "value123", isSecret: true)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EnvironmentVariable.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.key, original.key)
        XCTAssertEqual(decoded.value, original.value)
        XCTAssertEqual(decoded.isSecret, original.isSecret)
    }

    func testDecodingFromJSON() throws {
        let json = """
            {
                "id": "550e8400-e29b-41d4-a716-446655440000",
                "key": "API_TOKEN",
                "value": "abc123",
                "isSecret": true
            }
            """

        let decoder = JSONDecoder()
        let variable = try decoder.decode(EnvironmentVariable.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(variable.id.uuidString.uppercased(), "550E8400-E29B-41D4-A716-446655440000")
        XCTAssertEqual(variable.key, "API_TOKEN")
        XCTAssertEqual(variable.value, "abc123")
        XCTAssertTrue(variable.isSecret)
    }

    // MARK: - Equatable Tests

    func testEqualityById() {
        let id = UUID()
        let var1 = EnvironmentVariable(id: id, key: "KEY1", value: "value1", isSecret: false)
        let var2 = EnvironmentVariable(id: id, key: "KEY2", value: "value2", isSecret: true)

        // Equality is based on id
        XCTAssertEqual(var1, var2)
    }

    func testInequalityByDifferentId() {
        let var1 = EnvironmentVariable(key: "KEY", value: "value", isSecret: false)
        let var2 = EnvironmentVariable(key: "KEY", value: "value", isSecret: false)

        XCTAssertNotEqual(var1, var2)
    }

    // MARK: - Hashable Tests

    func testHashableById() {
        let id = UUID()
        let var1 = EnvironmentVariable(id: id, key: "KEY1", value: "value1", isSecret: false)
        let var2 = EnvironmentVariable(id: id, key: "KEY2", value: "value2", isSecret: true)

        var set = Set<EnvironmentVariable>()
        set.insert(var1)
        set.insert(var2)

        // Same id means only one entry in set
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - Edge Cases

    func testVeryLongKey() {
        let longKey = String(repeating: "A", count: 1000)
        let variable = EnvironmentVariable(key: longKey, value: "", isSecret: false)
        XCTAssertTrue(variable.isValidKey)
    }

    func testVeryLongValue() {
        let longValue = String(repeating: "X", count: 10000)
        let variable = EnvironmentVariable(key: "KEY", value: longValue, isSecret: false)
        XCTAssertEqual(variable.value.count, 10000)
    }

    func testUnicodeInValue() {
        let variable = EnvironmentVariable(key: "MSG", value: "Hello \u{1F600} World", isSecret: false)
        XCTAssertTrue(variable.value.contains("\u{1F600}"))
    }

    func testSingleCharacterKey() {
        let variable = EnvironmentVariable(key: "X", value: "value", isSecret: false)
        XCTAssertTrue(variable.isValidKey)
    }
}
