import XCTest

@testable import MCPServerLib

/// Enforces the CLI ⇄ MCP parity policy from audit §7.
///
/// Adding a new MCP tool without classifying it in `ToolParity.mandatoryCLI` or
/// `ToolParity.omittedCLI` fails CI here. This converts the policy from "we should
/// keep these in sync" to "the build won't pass if you don't."
final class ToolParityTests: XCTestCase {
    /// Every tool returned by the MCP server must appear in the parity registry, in
    /// exactly one of the two lists. Missing means the author forgot to classify it.
    func test_everyMCPToolIsClassified() {
        let toolNames = TermQMCPServer.availableTools.map { $0.name }
        let known = ToolParity.allKnownNames
        let unclassified = toolNames.filter { !known.contains($0) }
        XCTAssertTrue(
            unclassified.isEmpty,
            """
            New MCP tool(s) missing from Sources/MCPServerLib/ToolParity.swift: \(unclassified).

            Decide whether each one belongs in `mandatoryCLI` (a matching termqcli subcommand
            must exist) or `omittedCLI` (with a stated reason). The audit §7 parity table
            lists the policy.
            """
        )
    }

    /// A name cannot be in both lists — the classification is mutually exclusive.
    func test_classificationIsMutuallyExclusive() {
        let mandatory = Set(ToolParity.mandatoryCLI)
        let omitted = Set(ToolParity.omittedCLI.map { $0.name })
        let overlap = mandatory.intersection(omitted)
        XCTAssertTrue(
            overlap.isEmpty,
            "ToolParity classifies these tools in BOTH lists: \(overlap)"
        )
    }

    /// Every omission carries a non-empty reason — the docs generator surfaces these,
    /// so an unexplained omission would render as an empty line.
    func test_everyOmissionHasReason() {
        for entry in ToolParity.omittedCLI {
            XCTAssertFalse(
                entry.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Empty omission reason for \(entry.name)"
            )
        }
    }

    /// Mandatory-CLI entries must correspond to actual MCP tools — if a name appears
    /// here but not in `availableTools`, the registry is stale.
    func test_mandatoryClassificationsAreCurrentTools() {
        let toolNames = Set(TermQMCPServer.availableTools.map { $0.name })
        for name in ToolParity.mandatoryCLI where !toolNames.contains(name) {
            XCTFail(
                """
                ToolParity.mandatoryCLI references '\(name)' but no such MCP tool exists.
                Did you rename the tool without updating the registry?
                """
            )
        }
    }

    /// Same check for omissions — stale omissions are misleading.
    func test_omissionsAreCurrentTools() {
        let toolNames = Set(TermQMCPServer.availableTools.map { $0.name })
        for entry in ToolParity.omittedCLI where !toolNames.contains(entry.name) {
            XCTFail(
                """
                ToolParity.omittedCLI references '\(entry.name)' but no such MCP tool exists.
                Did you remove the tool without updating the registry?
                """
            )
        }
    }
}
