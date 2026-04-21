import XCTest

@testable import TermQ

final class InitCommandTokenizerTests: XCTestCase {

    private let tokenizer = InitCommandTokenizer()

    private func tokens(prompt: String = "", nextAction: String = "") -> InitCommandTokenizer.Tokens {
        .init(prompt: prompt, nextAction: nextAction)
    }

    // MARK: - Token replacement

    func testReplacePromptToken() {
        let result = tokenizer.replace("claude \"{{PROMPT}}\"", with: tokens(prompt: "Fix the bug"))
        XCTAssertEqual(result, "claude \"Fix the bug\"")
    }

    func testReplaceLegacyLLMPromptToken() {
        let result = tokenizer.replace("claude \"{{LLM_PROMPT}}\"", with: tokens(prompt: "Fix the bug"))
        XCTAssertEqual(result, "claude \"Fix the bug\"")
    }

    func testReplaceNextActionToken() {
        let result = tokenizer.replace("run {{NEXT_ACTION}}", with: tokens(nextAction: "npm test"))
        XCTAssertEqual(result, "run npm test")
    }

    func testReplaceLegacyLLMNextActionToken() {
        let result = tokenizer.replace("run {{LLM_NEXT_ACTION}}", with: tokens(nextAction: "npm test"))
        XCTAssertEqual(result, "run npm test")
    }

    func testReplaceBothTokensInTemplate() {
        let template = "claude \"{{PROMPT}}\" && {{NEXT_ACTION}}"
        let result = tokenizer.replace(template, with: tokens(prompt: "Context", nextAction: "make test"))
        XCTAssertEqual(result, "claude \"Context\" && make test")
    }

    func testReplaceAllFourTokens() {
        let template = "{{PROMPT}} {{LLM_PROMPT}} {{NEXT_ACTION}} {{LLM_NEXT_ACTION}}"
        let result = tokenizer.replace(template, with: tokens(prompt: "p", nextAction: "n"))
        XCTAssertEqual(result, "p p n n")
    }

    // MARK: - Edge cases

    func testNoTokensInTemplateReturnedUnchanged() {
        let template = "echo 'hello world'"
        let result = tokenizer.replace(template, with: tokens(prompt: "ignored", nextAction: "ignored"))
        XCTAssertEqual(result, template)
    }

    func testEmptyValuesProduceEmptySubstitution() {
        let template = "claude \"{{PROMPT}}\" {{NEXT_ACTION}}"
        let result = tokenizer.replace(template, with: tokens(prompt: "", nextAction: ""))
        XCTAssertEqual(result, "claude \"\" ")
    }

    func testEmptyTemplate() {
        let result = tokenizer.replace("", with: tokens(prompt: "p", nextAction: "n"))
        XCTAssertEqual(result, "")
    }

    func testTokensWithSpecialCharactersPassThrough() {
        // Escaping is the caller's concern; tokenizer does not modify values
        let result = tokenizer.replace("{{PROMPT}}", with: tokens(prompt: "it's $HOME `date`"))
        XCTAssertEqual(result, "it's $HOME `date`")
    }

    func testMultipleOccurrencesOfSameToken() {
        let result = tokenizer.replace("{{PROMPT}} and {{PROMPT}}", with: tokens(prompt: "hi"))
        XCTAssertEqual(result, "hi and hi")
    }
}
