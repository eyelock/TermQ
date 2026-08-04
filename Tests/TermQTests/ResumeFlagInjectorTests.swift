import XCTest

@testable import TermQ

/// The injector's job is narrow but unforgiving: `--resume` must land where
/// YNH reads flags, never inside the trailing prompt, and never twice.
final class ResumeFlagInjectorTests: XCTestCase {

    private let injector = ResumeFlagInjector()

    // MARK: - Placement

    func test_inject_appendsWhenThereIsNoPromptSeparator() {
        let result = injector.inject(into: "ynh run local/dev -v claude --session-name termq-abc")

        XCTAssertEqual(result, "ynh run local/dev -v claude --session-name termq-abc --resume")
    }

    /// Anything after the `--` separator is the prompt, so appending there
    /// would hand "--resume" to the LLM as text instead of to YNH as a flag.
    func test_inject_insertsBeforeThePromptSeparator() {
        let result = injector.inject(into: "ynh run local/dev -v claude -- 'fix the build'")

        XCTAssertEqual(result, "ynh run local/dev -v claude --resume -- 'fix the build'")
    }

    func test_inject_placesFlagBeforeSeparatorEvenWithManyFlags() {
        let command = "ynh run local/dev -v claude --focus review --interactive -- \"do the thing\""

        let result = injector.inject(into: command)

        XCTAssertEqual(
            result,
            "ynh run local/dev -v claude --focus review --interactive --resume -- \"do the thing\""
        )
    }

    /// A `--` inside the quoted prompt must not be mistaken for the separator.
    func test_inject_ignoresDoubleDashInsideAQuotedPrompt() {
        let result = injector.inject(into: "ynh run local/dev -- \"run make -- verbose\"")

        XCTAssertEqual(result, "ynh run local/dev --resume -- \"run make -- verbose\"")
    }

    // MARK: - Idempotence

    func test_inject_isIdempotent() {
        let once = injector.inject(into: "ynh run local/dev")
        let twice = injector.inject(into: once)

        XCTAssertEqual(once, twice)
    }

    /// An id the user typed by hand always wins — never append a second,
    /// bare flag alongside it.
    func test_inject_leavesAnExplicitSessionIdAlone() {
        let command = "ynh run local/dev --resume=6187c041-ee79-4646-b101-82f89c3e50ca"

        XCTAssertEqual(injector.inject(into: command), command)
    }

    func test_inject_leavesAnExistingBareFlagAlone() {
        let command = "ynh run local/dev --resume -- 'carry on'"

        XCTAssertEqual(injector.inject(into: command), command)
    }

    /// "--resume" appearing as prose inside the prompt is not a flag, so the
    /// real flag must still be added.
    func test_inject_treatsResumeInsideAQuotedPromptAsProse() {
        let result = injector.inject(into: "ynh run local/dev -- \"explain how --resume works\"")

        XCTAssertEqual(result, "ynh run local/dev --resume -- \"explain how --resume works\"")
    }

    // MARK: - Degenerate input

    func test_inject_leavesEmptyCommandUntouched() {
        XCTAssertEqual(injector.inject(into: ""), "")
        XCTAssertEqual(injector.inject(into: "   "), "   ")
    }

    // MARK: - Detection

    func test_containsResumeFlag() {
        XCTAssertTrue(injector.containsResumeFlag("ynh run x --resume"))
        XCTAssertTrue(injector.containsResumeFlag("ynh run x --resume=abc"))
        XCTAssertFalse(injector.containsResumeFlag("ynh run x"))
        // Neither a different flag that merely starts the same way...
        XCTAssertFalse(injector.containsResumeFlag("ynh run x --resumeable"))
        // ...nor the word appearing inside the prompt.
        XCTAssertFalse(injector.containsResumeFlag("ynh run x -- 'talk about --resume'"))
    }
}
