import Foundation

/// Fixes names and terms the speech model misspells, using the user's personal dictionary.
///
/// "Hi DeVeo, how are you?" + ["Divya"] → "Hi Divya, how are you?"
///
/// Deliberately conservative — a word is only replaced when all of these hold:
///  1. it is not a real English word (`isKnownWord`), so "river" can never become "Aarav";
///  2. it sounds like a dictionary term (same consonant skeleton: D-V ≈ D-V);
///  3. its spelling is reasonably close (similarity ≥ 0.4).
/// Exact matches in any casing are always normalized to the dictionary spelling ("iphone" → "iPhone").
public struct PersonalDictionary: Sendable {
    public let terms: [String]
    private let entries: [(term: String, lower: String, keys: Set<String>)]

    public init(_ terms: [String]) {
        self.terms = terms
        entries = terms.compactMap { term in
            let t = term.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.contains(" ") else { return nil } // single words for now
            return (t, t.lowercased(), Self.keys(t))
        }
    }

    public var isEmpty: Bool { entries.isEmpty }

    public func apply(_ text: String, isKnownWord: (String) -> Bool) -> String {
        guard !entries.isEmpty else { return text }
        return text.split(separator: " ", omittingEmptySubsequences: false).map { piece -> String in
            let token = String(piece)
            // Split off surrounding punctuation: "DeVeo," → ("", "DeVeo", ",").
            let chars = Array(token)
            guard let first = chars.firstIndex(where: \.isLetter),
                  let last = chars.lastIndex(where: \.isLetter) else { return token }
            let word = String(chars[first ... last])
            guard word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "-" }) else { return token }
            guard let replacement = match(word, isKnownWord: isKnownWord) else { return token }
            return String(chars[..<first]) + replacement + String(chars[(last + 1)...])
        }.joined(separator: " ")
    }

    func match(_ word: String, isKnownWord: (String) -> Bool) -> String? {
        let lower = word.lowercased()
        if let exact = entries.first(where: { $0.lower == lower }) { return exact.term }
        guard lower.count >= 3, !Self.isKnown(lower, isKnownWord) else { return nil }
        let wordKeys = Self.keys(word)
        let best = entries
            .filter { !$0.keys.isDisjoint(with: wordKeys) }
            .map { (term: $0.term, score: Self.similarity(lower, $0.lower)) }
            .max { $0.score < $1.score }
        guard let best, best.score >= 0.4 else { return nil }
        return best.term
    }

    /// Known words, including simple inflections the word list leaves out ("walked", "calls").
    static func isKnown(_ w: String, _ isKnownWord: (String) -> Bool) -> Bool {
        if isKnownWord(w) { return true }
        let stripped = w.replacingOccurrences(of: "'", with: "")
        if stripped != w, isKnownWord(stripped) { return true }
        for suffix in ["s", "es", "ed", "d", "ing", "ly", "er", "ers", "'s", "n't"] where w.hasSuffix(suffix) {
            let base = String(w.dropLast(suffix.count))
            if base.count >= 2, isKnownWord(base) || isKnownWord(base + "e") { return true }
        }
        return false
    }

    // MARK: - Phonetics

    /// Consonant skeletons, with and without a leading vowel ("Aarav" → ARF, RF; "Rav" → RF).
    static func keys(_ word: String) -> Set<String> {
        let full = skeleton(word)
        var keys: Set<String> = [full]
        if full.first == "A", full.count > 1 { keys.insert(String(full.dropFirst())) }
        return keys
    }

    /// Letters → sound classes, vowels dropped (except a leading one), repeats collapsed.
    static func skeleton(_ word: String) -> String {
        var s = word.lowercased().filter { $0.isASCII && $0.isLetter }
        for (digraph, single) in [("ph", "f"), ("sh", "s"), ("ch", "c"), ("th", "t"), ("kh", "k"),
                                  ("gh", "g"), ("bh", "b"), ("dh", "d"), ("ck", "k")]
        {
            s = s.replacingOccurrences(of: digraph, with: single)
        }
        var out = ""
        for (i, c) in s.enumerated() {
            let cls: Character? = switch c {
            case "a", "e", "i", "o", "u", "y": i == 0 ? "A" : nil
            case "b", "p": "B"
            case "f", "v", "w": "F"
            case "c", "g", "k", "q": "K"
            case "d", "t": "T"
            case "s", "z", "x": "S"
            case "j": "J"
            case "l": "L"
            case "r": "R"
            case "m", "n": "N"
            default: nil // h
            }
            if let cls, out.last != cls { out.append(cls) }
        }
        return out
    }

    /// 1 − normalized Levenshtein distance.
    static func similarity(_ a: String, _ b: String) -> Double {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var prev = Array(0 ... b.count)
        for i in 1 ... a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1 ... b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return 1 - Double(prev[b.count]) / Double(max(a.count, b.count))
    }
}
