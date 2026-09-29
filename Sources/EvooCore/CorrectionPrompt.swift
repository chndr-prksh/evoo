import Foundation

/// Self-correction by a small local LLM, framed as *deletion only*.
///
/// The model sees the transcript with numbered words and answers with the numbers to delete
/// ("3-4"), not a rewrite. That keeps output to a few tokens (fast on a laptop) and makes it
/// impossible for the model to invent, answer or rephrase anything: it can only remove words
/// the speaker took back, and every answer is validated before use.
public enum CorrectionPrompt {
    /// Words that signal the speaker is correcting themselves. The LLM only runs when one is present.
    public static let cues: Set<String> = [
        "no", "not", "sorry", "actually", "mean", "meant", "wait", "scratch", "rather", "correction", "instead",
    ]

    public static func hasCue(_ text: String) -> Bool {
        words(text).contains { cues.contains(normalize($0)) }
    }

    public static let system = """
    You fix self-corrections in dictated text. The words are numbered. When the speaker corrects \
    themselves, answer with the numbers of the words to delete: the part they took back and the \
    correction words (no, sorry, actually, I mean, wait, not…). Keep the correction itself. \
    If nothing was corrected, answer none. Answer only with numbers and ranges.
    """

    public struct Example: Sendable {
        public let text: String
        public let answer: String
    }

    public static let examples: [Example] = [
        .init(text: "Let's meet tomorrow, no, day after tomorrow.", answer: "3-4"),
        .init(text: "Email him, no, call him.", answer: "1-3"),
        .init(text: "Ask Sarah, no, ask Emma to review it.", answer: "1-3"),
        .init(text: "There is no milk in the fridge.", answer: "none"),
        .init(text: "Send it to John, not John, Mike.", answer: "4-6"),
        .init(text: "I think we should, actually let's just ship it.", answer: "1-5"),
        .init(text: "Book a table for 4, no, 6 people.", answer: "5-6"),
        .init(text: "Sorry for the late reply.", answer: "none"),
        .init(text: "Make the button blue, actually green.", answer: "4-5"),
        .init(text: "I'm free tomorrow, not today.", answer: "none"),
    ]

    public static func numbered(_ text: String) -> String {
        words(text).enumerated().map { "\($0.offset + 1) \($0.element)" }.joined(separator: " ")
    }

    /// Qwen ChatML; static part (cached in the KV cache) and per-dictation part.
    public static var prefix: String {
        var p = "<|im_start|>system\n\(system)<|im_end|>\n"
        for ex in examples {
            p += "<|im_start|>user\n\(numbered(ex.text))<|im_end|>\n<|im_start|>assistant\n\(ex.answer)<|im_end|>\n"
        }
        return p
    }

    public static func suffix(_ text: String, thinkBlock: Bool) -> String {
        "<|im_start|>user\n\(numbered(text))<|im_end|>\n<|im_start|>assistant\n" + (thinkBlock ? "<think>\n\n</think>\n\n" : "")
    }

    /// Parses "3-4", "2, 6-8" or "none" into 0-based word indices.
    public static func parse(_ answer: String) -> Set<Int>? {
        let a = answer.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if a.hasPrefix("none") { return [] }
        var out: Set<Int> = []
        for part in a.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" }) {
            let ends = part.split(separator: "-").compactMap { Int($0.filter(\.isNumber)) }
            switch ends.count {
            case 1: out.insert(ends[0] - 1)
            case 2 where ends[0] <= ends[1]: out.formUnion((ends[0] - 1) ... (ends[1] - 1))
            default: return nil
            }
        }
        return out.isEmpty ? nil : out
    }

    /// Applies the deletions if they look like a real self-correction; nil means "don't trust it".
    public static func apply(_ indices: Set<Int>, to text: String) -> String? {
        var tokens = words(text)
        guard !indices.isEmpty else { return text }
        guard indices.allSatisfy({ $0 >= 0 && $0 < tokens.count }),
              indices.count < tokens.count, // something must remain
              Double(indices.count) <= Double(tokens.count) * 0.7,
              indices.contains(where: { cues.contains(normalize(tokens[$0])) }) // the cue itself must go
        else { return nil }

        // Keep the sentence's final punctuation if its last word was deleted.
        let finalPunct = tokens.last.map { String($0.reversed().prefix { ".?!".contains($0) }.reversed()) } ?? ""
        let kept = tokens.indices.filter { !indices.contains($0) }
        for (n, i) in kept.enumerated() {
            let deletedAfter = indices.contains(i + 1)
            if deletedAfter, n + 1 < kept.count { tokens[i] = tokens[i].trimmingCharacters(in: CharacterSet(charactersIn: ",;")) }
        }
        var out = kept.map { tokens[$0] }
        guard !out.isEmpty else { return nil }
        // Strip a comma left right before the kept correction, capitalize a new first word, restore the end.
        if indices.contains(0), let f = out[0].first { out[0] = f.uppercased() + out[0].dropFirst() }
        if let last = out.last, !last.hasSuffix(finalPunct) {
            out[out.count - 1] = last.trimmingCharacters(in: CharacterSet(charactersIn: ",;.?!")) + finalPunct
        }
        return out.joined(separator: " ")
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func normalize(_ w: String) -> String {
        w.lowercased().filter(\.isLetter)
    }
}
