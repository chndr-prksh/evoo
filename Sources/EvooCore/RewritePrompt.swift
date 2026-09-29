import Foundation

/// "Rewrite by voice": select text, hold fn, say what to do with it ("make this more formal").
/// Handled by the local LLM (16 GB+ Macs).
public enum RewritePrompt {
    /// A dictation over a selection counts as an instruction only if it reads like one — otherwise
    /// it's ordinary dictation that replaces the selection.
    public static func isInstruction(_ dictation: String) -> Bool {
        dictation.range(of: #"^(?i)\s*(?:please |can you |could you )?(?:make (?:this|it|that)|rewrite|rephrase|reword|shorten|expand|summari[sz]e|translate|fix (?:the )?(?:grammar|spelling|this)|turn (?:this|it) into|change the tone|polish|simplify|proofread|write (?:this|it) (?:as|more))\b"#,
                          options: .regularExpression) != nil
    }

    static let system = """
    You rewrite text for the user. You receive an instruction and the text. Apply the instruction and output \
    ONLY the rewritten text: no preamble, no quotes, no explanation. Keep the meaning, names, numbers and \
    facts. Keep the same language unless the instruction asks to translate.
    """

    /// Qwen ChatML; the system part is static (cached in the KV cache).
    public static var prefix: String {
        "<|im_start|>system\n\(system)<|im_end|>\n"
    }

    public static func suffix(instruction: String, text: String, thinkBlock: Bool) -> String {
        "<|im_start|>user\nInstruction: \(instruction)\n\nText:\n\(text)<|im_end|>\n<|im_start|>assistant\n"
            + (thinkBlock ? "<think>\n\n</think>\n\n" : "")
    }

    public static func sanitize(_ output: String) -> String {
        RefinePrompt.sanitize(output)
            .replacingOccurrences(of: #"^(?i)(here(?:'s| is) (?:the )?rewritten text:?\s*)"#, with: "",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
