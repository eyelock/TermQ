import Foundation

/// Replaces template tokens in init command strings.
/// Escaping of injected values is the caller's responsibility.
struct InitCommandTokenizer {

    struct Tokens {
        let prompt: String
        let nextAction: String
    }

    /// Replaces all `{{PROMPT}}`, `{{LLM_PROMPT}}`, `{{NEXT_ACTION}}`,
    /// and `{{LLM_NEXT_ACTION}}` tokens in `template` with the supplied values.
    func replace(_ template: String, with tokens: Tokens) -> String {
        template
            .replacingOccurrences(of: "{{PROMPT}}", with: tokens.prompt)
            .replacingOccurrences(of: "{{LLM_PROMPT}}", with: tokens.prompt)
            .replacingOccurrences(of: "{{NEXT_ACTION}}", with: tokens.nextAction)
            .replacingOccurrences(of: "{{LLM_NEXT_ACTION}}", with: tokens.nextAction)
    }
}
