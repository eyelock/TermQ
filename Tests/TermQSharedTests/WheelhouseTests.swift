import Foundation
import XCTest

@testable import TermQShared

final class WheelhouseTests: XCTestCase {

    var tempDirectory: URL!

    override func setUpWithError() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermQ-WheelhouseTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectory = tempDir
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // A roster shaped like ynw's: extra top-level keys, a desk without a role,
    // specialities, seated-by, and an unknown group.
    private let ynwShaped = """
        {
          "pools": {"crew": {"theme": "Record producers", "names": ["Eno"]}},
          "excluded": [{"name": "Hook", "reason": "too close to hooks"}],
          "humans": [{"name": "Stakker", "command": "stakker", "default": true}],
          "models": {"groups": {"desk": "deep"}},
          "seats": [
            {"name": "Hynde", "group": "workers", "command": "hynde", "harness": "harnesses/hynde",
             "mandate": "Builds ynh beads.", "seated-by": "marr", "role": "specialist-worker",
             "specialities": ["repo:ynh", "area:docs"], "pronouns": "she/her"},
            {"name": "ynw", "group": "desk", "command": "ynw", "mandate": "Talks with the human."},
            {"name": "Eno", "group": "crew", "command": "eno", "role": "designer"},
            {"name": "May", "group": "standing", "command": "may", "role": "verifier"},
            {"name": "Odd", "group": "moot", "command": "odd", "role": "release-captain"}
          ]
        }
        """

    private func decode(_ json: String) throws -> WheelhouseRoster {
        try JSONDecoder().decode(WheelhouseRoster.self, from: Data(json.utf8))
    }

    private func writeRoster(_ json: String, in folder: String) throws -> String {
        let root = tempDirectory.appendingPathComponent(folder)
        let assets = root.appendingPathComponent("skills/roster/assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: assets.appendingPathComponent("roster.json"))
        return root.path
    }

    // MARK: - Decoding

    func testDecodesYnwShapedRosterIgnoringUnknownKeys() throws {
        let roster = try decode(ynwShaped)
        XCTAssertEqual(roster.seats.map(\.command), ["hynde", "ynw", "eno", "may", "odd"])
        XCTAssertNil(roster.version)
        XCTAssertNil(roster.wheelhouse)

        let hynde = roster.seats[0]
        XCTAssertEqual(hynde.name, "Hynde")
        XCTAssertEqual(hynde.group, .workers)
        XCTAssertEqual(hynde.harness, "harnesses/hynde")
        XCTAssertEqual(hynde.mandate, "Builds ynh beads.")
        XCTAssertEqual(hynde.role, .specialistWorker)
        XCTAssertEqual(hynde.pronouns, "she/her")
        XCTAssertEqual(hynde.id, "hynde")
    }

    func testVersionAndTitleAreRead() throws {
        let roster = try decode(
            """
            {"v": 1, "wheelhouse": {"title": "YN-dev Wheelhouse"}, "seats": []}
            """)
        XCTAssertEqual(roster.version, 1)
        XCTAssertEqual(roster.wheelhouse?.title, "YN-dev Wheelhouse")
    }

    func testMalformedSeatIsSkippedNotFatal() throws {
        let roster = try decode(
            """
            {"seats": [{"name": "NoCommand", "group": "crew"}, {"name": "Eno", "group": "crew", "command": "eno"}]}
            """)
        XCTAssertEqual(roster.seats.map(\.command), ["eno"])
    }

    func testMissingSeatsGivesEmptyRoster() throws {
        XCTAssertEqual(try decode("{}").seats, [])
    }

    func testMissingGroupBecomesOther() throws {
        let roster = try decode(#"{"seats": [{"name": "A", "command": "a"}]}"#)
        XCTAssertEqual(roster.seats.first?.group, .other(""))
    }

    // MARK: - Roles and groups

    func testRoleSlugsMapToKnownRoles() {
        let pairs: [(String, WheelhouseRole)] = [
            ("desk", .desk), ("designer", .designer), ("reviewer", .reviewer),
            ("dispatcher", .dispatcher), ("ci-watcher", .ciWatcher), ("releaser", .releaser),
            ("verifier", .verifier), ("programme-manager", .programmeManager),
            ("program-manager", .programmeManager), ("tutor", .tutor),
            ("specialist-worker", .specialistWorker), ("worker", .worker),
        ]
        for (slug, role) in pairs {
            XCTAssertEqual(WheelhouseRole(rawValue: slug), role, slug)
        }
        XCTAssertEqual(WheelhouseRole.ciWatcher.rawValue, "ci-watcher")
    }

    func testUnknownRoleKeepsSlugAndTitleCases() {
        let role = WheelhouseRole(rawValue: "release-captain")
        XCTAssertEqual(role, .other("release-captain"))
        XCTAssertEqual(role.titleCasedSlug, "Release Captain")
        XCTAssertEqual(role.symbolName, "person")
    }

    func testDeskWithoutRoleGetsDeskRole() throws {
        let roster = try decode(ynwShaped)
        let desk = try XCTUnwrap(roster.seats.first { $0.command == "ynw" })
        XCTAssertNil(desk.role)
        XCTAssertEqual(desk.effectiveRole, .desk)

        let odd = try XCTUnwrap(roster.seats.first { $0.command == "odd" })
        XCTAssertEqual(odd.group, .other("moot"))
        XCTAssertEqual(odd.effectiveRole, .other("release-captain"))
    }

    func testNonDeskWithoutRoleHasNoEffectiveRole() {
        let seat = WheelhouseSeat(name: "A", group: .crew, command: "a")
        XCTAssertNil(seat.effectiveRole)
    }

    func testRepositoriesComeFromRepoSpecialitiesOnly() {
        let seat = WheelhouseSeat(
            name: "Ferry", group: .workers, command: "ferry",
            specialities: ["repo:ynf", "area:docs", "repo:", "repo:ynh"])
        XCTAssertEqual(seat.repositories, ["ynf", "ynh"])
    }

    func testSeatsByGroupUsesPluginOrderThenUnknownGroups() throws {
        let wheelhouse = Wheelhouse(root: "/x/ynw", roster: try decode(ynwShaped))
        let groups = wheelhouse.seatsByGroup
        XCTAssertEqual(groups.map(\.group), [.desk, .crew, .standing, .workers, .other("moot")])
        XCTAssertEqual(groups.map { $0.seats.map(\.command) }, [["ynw"], ["eno"], ["may"], ["hynde"], ["odd"]])
    }

    // MARK: - Title

    func testTitleFallsBackToFolderName() {
        let wheelhouse = Wheelhouse(root: "/Users/me/ynw", roster: WheelhouseRoster(seats: []))
        XCTAssertEqual(wheelhouse.title, "ynw")
        XCTAssertEqual(wheelhouse.name, "ynw")
    }

    func testBlankTitleFallsBackToFolderName() {
        let wheelhouse = Wheelhouse(
            root: "/Users/me/ynw", roster: WheelhouseRoster(wheelhouse: .init(title: "  "), seats: []))
        XCTAssertEqual(wheelhouse.title, "ynw")
    }

    func testTitleFromRoster() {
        let wheelhouse = Wheelhouse(
            root: "/Users/me/ynw",
            roster: WheelhouseRoster(wheelhouse: .init(title: "YN-dev Wheelhouse"), seats: []))
        XCTAssertEqual(wheelhouse.title, "YN-dev Wheelhouse")
    }

    // MARK: - Loading and discovery

    func testLoadReturnsNilWithoutRoster() throws {
        let plain = tempDirectory.appendingPathComponent("plain")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        XCTAssertNil(try WheelhouseLoader.load(root: plain.path))
        XCTAssertFalse(WheelhouseLoader.isWheelhouse(root: plain.path))
    }

    func testLoadReadsRoster() throws {
        let root = try writeRoster(ynwShaped, in: "ynw")
        XCTAssertTrue(WheelhouseLoader.isWheelhouse(root: root))
        let wheelhouse = try XCTUnwrap(try WheelhouseLoader.load(root: root))
        XCTAssertEqual(wheelhouse.root, root)
        XCTAssertEqual(wheelhouse.seats.count, 5)
    }

    func testLoadThrowsOnBrokenRoster() throws {
        let root = try writeRoster("{ not json", in: "broken")
        XCTAssertThrowsError(try WheelhouseLoader.load(root: root))
    }

    func testDiscoverFindsWheelhousesKeepsOrderAndReportsFailures() throws {
        let second = try writeRoster(#"{"seats": [{"name": "A", "group": "desk", "command": "a"}]}"#, in: "second")
        let ynw = try writeRoster(ynwShaped, in: "ynw")
        let broken = try writeRoster("{ not json", in: "broken")
        let plain = tempDirectory.appendingPathComponent("plain")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)

        let result = WheelhouseLoader.discover(roots: [second, plain.path, ynw, broken, second + "/"])
        XCTAssertEqual(result.wheelhouses.map(\.name), ["second", "ynw"])
        XCTAssertEqual(result.failures.map(\.root), [URL(fileURLWithPath: broken).standardizedFileURL.path])
    }

    func testSeatRoundTripsThroughEncoding() throws {
        let seat = WheelhouseSeat(
            name: "Reni", group: .standing, command: "reni", harness: "harnesses/reni",
            mandate: "Watches CI.", role: .ciWatcher, specialities: ["repo:ynh"], pronouns: "they/them")
        let data = try JSONEncoder().encode(seat)
        XCTAssertEqual(try JSONDecoder().decode(WheelhouseSeat.self, from: data), seat)
    }
}
