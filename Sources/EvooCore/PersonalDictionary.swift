import Foundation

/// Fixes names and terms the speech model misspells, using the user's personal dictionary.
///
/// "Hi DeVeo, how are you?" + ["Divya"] → "Hi Divya, how are you?"
///
/// Deliberately conservative — a word is only replaced when all of these hold:
///  1. it is not a real English word (`isKnownWord`), so "river" can never become "Aarav" — unless the
///     speech model capitalized it mid-sentence (it heard a name: "your name Deva" → "Divya");
///  2. it sounds like a dictionary term (same consonant skeleton: D-V ≈ D-V);
///  3. its spelling is reasonably close (similarity ≥ 0.4).
/// Exact matches in any casing are always normalized to the dictionary spelling ("iphone" → "iPhone").
public struct PersonalDictionary: Sendable {
    public let terms: [String]
    private let entries: [(term: String, lower: String, keys: Set<String>)]
    /// Multi-word terms ("Wispr Flow"), matched by their letters without spaces ("wisprflow").
    private let phrases: [(term: String, joined: String, words: Int, skeleton: String)]

    public init(_ terms: [String]) {
        self.terms = terms
        let cleaned = terms.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        entries = cleaned.filter { !$0.contains(" ") }.map { ($0, $0.lowercased(), Self.keys($0)) }
        phrases = cleaned.filter { $0.contains(" ") }.map { term in
            let joined = term.lowercased().filter(\.isLetter)
            return (term, joined, term.split(separator: " ").count, Self.skeleton(joined))
        }
    }

    public var isEmpty: Bool { entries.isEmpty && phrases.isEmpty }

    public func apply(_ text: String, isKnownWord: (String) -> Bool) -> String {
        guard !isEmpty else { return text }
        let withPhrases = applyPhrases(text, isKnownWord: isKnownWord)
        guard !entries.isEmpty else { return withPhrases }
        let pieces = withPhrases.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        return pieces.enumerated().map { index, token -> String in
            let sentenceStart = index == 0 || pieces[index - 1].last.map { ".?!\n".contains($0) } == true
            // Split off surrounding punctuation: "DeVeo," → ("", "DeVeo", ",").
            let chars = Array(token)
            guard let first = chars.firstIndex(where: \.isLetter),
                  let last = chars.lastIndex(where: \.isLetter) else { return token }
            let word = String(chars[first ... last])
            guard word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "-" }) else { return token }
            let heardAsName = !sentenceStart && word.first?.isUppercase == true
            guard let replacement = match(word, isKnownWord: isKnownWord, heardAsName: heardAsName) else { return token }
            return String(chars[..<first]) + replacement + String(chars[(last + 1)...])
        }.joined(separator: " ")
    }

    /// "whisperflow" or "whisper flow" → "Wispr Flow". A run of the same number of words (or one unknown
    /// word) whose letters sound like the phrase and are spelled almost the same.
    func applyPhrases(_ text: String, isKnownWord: (String) -> Bool) -> String {
        guard !phrases.isEmpty else { return text }
        var words = text.split(separator: " ").map(String.init)
        for phrase in phrases {
            for n in Set([phrase.words, 1]).sorted(by: >) {
                var i = 0
                while i + n <= words.count {
                    let span = words[i ..< i + n]
                    let letters = span.joined().lowercased().filter(\.isLetter)
                    let single = n == 1 ? span.first!.lowercased().filter(\.isLetter) : ""
                    let eligible = n > 1 || !Self.isKnown(single, isKnownWord)
                    if eligible, !letters.isEmpty, letters == phrase.joined
                        || (Self.skeleton(letters) == phrase.skeleton && Self.similarity(letters, phrase.joined) >= 0.75)
                    {
                        let trailing = String(span.last!.reversed().prefix { !$0.isLetter }.reversed())
                        let leading = String(span.first!.prefix { !$0.isLetter })
                        words.replaceSubrange(i ..< i + n, with: [leading + phrase.term + trailing])
                    }
                    i += 1
                }
            }
        }
        return words.joined(separator: " ")
    }

    func match(_ word: String, isKnownWord: (String) -> Bool, heardAsName: Bool = false) -> String? {
        let lower = word.lowercased()
        if let exact = entries.first(where: { $0.lower == lower }) { return exact.term }
        let known = Self.isKnown(lower, isKnownWord)
        guard lower.count >= 3, !known || heardAsName else { return nil }
        let wordKeys = Self.keys(word)
        let best = entries
            .filter { !$0.keys.isDisjoint(with: wordKeys) }
            .map { (term: $0.term, score: Self.similarity(lower, $0.lower)) }
            .max { $0.score < $1.score }
        // A real word the model heard as a name needs a closer spelling ("Deva" ~ "Divya").
        guard let best, best.score >= (known ? 0.6 : 0.4) else { return nil }
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
