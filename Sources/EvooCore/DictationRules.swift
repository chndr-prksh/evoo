import Foundation

/// Deterministic dictation cleanup that runs in microseconds, so most dictations never need the LLM:
///  • filler words:     "um so we should ship"               → "so we should ship"
///  • stutters:         "we could we could push it"          → "we could push it"
///  • self-corrections: "let's meet tomorrow, no, day after tomorrow" → "let's meet day after tomorrow"
///                      "send it to Rahul, sorry, to Priya"  → "send it to Priya"
///                      "at 3:30 actually make it 4"         → "at 4"
///                      "... scratch that ..."               → drops the previous sentence
///
/// When a correction cue is found but the rules can't tell what it replaces, `unresolved` is set
/// and the caller may hand the text to the LLM refiner.
public enum DictationRules {
    public struct Result: Equatable, Sendable {
        public var text: String
        /// A correction cue was present but no rule could apply it confidently.
        public var unresolved: Bool

        public init(text: String, unresolved: Bool) {
            self.text = text
            self.unresolved = unresolved
        }
    }

    public static func apply(_ input: String) -> Result {
        var tokens = normalizeMeridiem(input).split(whereSeparator: \.isWhitespace).map { Token(String($0)) }
        tokens = removeFillers(tokens)
        tokens = removeStutters(tokens)
        tokens = collapseValueCorrections(tokens)
        var unresolved = false
        tokens = applyCorrections(tokens, unresolved: &unresolved)
        return Result(text: render(tokens), unresolved: unresolved)
    }

    // MARK: - Tokens

    struct Token: Equatable {
        var raw: String
        /// Lowercased letters/digits only — used for matching.
        var norm: String { Token.normalize(raw) }
        var endsClause: Bool { raw.last.map { ",;:".contains($0) } ?? false }
        var endsSentence: Bool { raw.last.map { ".?!".contains($0) } ?? false }

        init(_ raw: String) { self.raw = raw }

        static func normalize(_ s: String) -> String {
            String(s.lowercased().unicodeScalars.filter {
                CharacterSet.alphanumerics.contains($0) || $0 == ":"
            }.map(Character.init)).trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        }

        /// The word without trailing punctuation, keeping the original casing.
        var bare: String { String(raw.reversed().drop { ",;:.?!".contains($0) }.reversed()) }
        var trailingPunctuation: String { String(raw.dropFirst(bare.count)) }
    }

    // MARK: - Fillers & stutters

    static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "uhm", "erm", "er", "hmm", "mm", "mhm", "ah"]

    static func removeFillers(_ tokens: [Token]) -> [Token] {
        var out: [Token] = []
        for t in tokens {
            if fillers.contains(t.norm) {
                // Keep sentence-ending punctuation the filler carried ("… ship it, um." → "… ship it.").
                if t.endsSentence, var last = out.popLast() {
                    last.raw = last.bare + t.trailingPunctuation
                    out.append(last)
                }
                continue
            }
            out.append(t)
        }
        return out
    }

    static func removeStutters(_ tokens: [Token]) -> [Token] {
        var t = tokens
        var changed = true
        while changed {
            changed = false
            outer: for n in stride(from: 4, through: 1, by: -1) where t.count >= 2 * n {
                for i in 0 ... (t.count - 2 * n) {
                    let a = t[i ..< i + n].map(\.norm), b = t[i + n ..< i + 2 * n].map(\.norm)
                    guard a == b, !a.contains(""), !(n == 1 && legitDoubles.contains(a[0])) else { continue }
                    // Keep the second copy — it carries the punctuation that follows. If ASR put a sentence
                    // break inside the stutter ("we could. We could"), undo the capital it added.
                    let wasLowercase = t[i].raw.first?.isLowercase == true
                    t.removeSubrange(i ..< i + n)
                    if wasLowercase, i == 0 || !t[i - 1].endsSentence, let f = t[i].raw.first {
                        t[i].raw = f.lowercased() + t[i].raw.dropFirst()
                    }
                    changed = true
                    break outer
                }
            }
        }
        return t
    }

    /// Words that are legitimately doubled in normal speech ("I know that that is…", "had had").
    static let legitDoubles: Set<String> = ["that", "had", "is", "very", "really", "bye", "no", "ha"]

    // MARK: - a.m. / p.m.

    /// "4 p.m." → "4 PM" so the dots aren't mistaken for sentence ends ("at 4 p.m. 5 p.m.").
    static func normalizeMeridiem(_ text: String) -> String {
        // At the end, or before a new sentence, the dot doubles as the full stop.
        var out = text.replacingOccurrences(of: #"(?i)\b([ap])\.\s?m\.(?=\s*$|\s+[A-Z])"#, with: "$1M.",
                                            options: .regularExpression)
        out = out.replacingOccurrences(of: #"(?i)\b([ap])\.\s?m\.?"#, with: "$1M", options: .regularExpression)
        return out.replacingOccurrences(of: "aM", with: "AM").replacingOccurrences(of: "pM", with: "PM")
    }

    // MARK: - Value corrections

    /// Chains of times/numbers or days joined by correction words; the last value that survives wins.
    ///   "at 4, not 4 PM, 5 PM"        → "at 5 PM"   (not = reject the next value; a bare restatement replaces)
    ///   "on Monday, sorry, Tuesday"   → "on Tuesday"
    ///   "at 5, not 4"                 → unchanged   (nothing was corrected, just ruled out)
    static func collapseValueCorrections(_ input: [Token]) -> [Token] {
        var t = input
        var i = 0
        while i < t.count {
            guard let first = valueGroup(in: t, at: i) else { i += 1; continue }
            var kept = first
            var last = first
            var corrected = false
            var awaitingRestatement = false
            var j = first.upperBound
            while j < t.count {
                // The words between two values must all be correction words (or nothing but a comma).
                var k = j
                while k < t.count, cueFiller.contains(t[k].norm) { k += 1 }
                let gap = t[j ..< k].map(\.norm)
                guard let next = valueGroup(in: t, at: k), valueClass(t[next.lowerBound]) == valueClass(t[first.lowerBound])
                else { break }
                let replaces = gap.contains { replacingCues.contains($0) } || gap.contains("mean")
                let negates = gap.contains("not")
                let commaOnly = gap.isEmpty && t[last.upperBound - 1].endsClause
                if negates, !replaces {
                    awaitingRestatement = true // "not 4 PM" — that value is rejected
                } else if replaces || (gap.isEmpty && awaitingRestatement) || (commaOnly && corrected) {
                    kept = next
                    corrected = true
                    awaitingRestatement = false
                } else { break }
                last = next
                j = next.upperBound
            }
            if corrected {
                var replacement = Array(t[kept])
                let tail = t[last.upperBound - 1].trailingPunctuation
                if let end = replacement.indices.last {
                    replacement[end].raw = replacement[end].bare + (tail.contains(where: { ".?!".contains($0) }) ? String(tail.last!) : "")
                }
                t.replaceSubrange(first.lowerBound ..< last.upperBound, with: replacement)
                i = first.lowerBound + replacement.count
            } else {
                i = first.upperBound
            }
        }
        return t
    }

    static let replacingCues: Set<String> = ["no", "sorry", "actually", "wait", "rather", "correction", "make", "meant", "nahi"]
    static let cueFiller: Set<String> = replacingCues.union(["not", "i", "mean", "it", "that", "or", "oh"])

    /// A run of tokens forming one value: "4 PM", "3:30", "five thirty", "Tuesday".
    static func valueGroup(in t: [Token], at i: Int) -> Range<Int>? {
        guard i < t.count, let cls = valueClass(t[i]) else { return nil }
        var end = i + 1
        // A group ends at punctuation or after AM/PM ("4 PM 5 PM" is two times).
        while end < t.count, !t[end - 1].endsClause, !t[end - 1].endsSentence,
              !["am", "pm"].contains(t[end - 1].norm), valueClass(t[end]) == cls { end += 1 }
        return i ..< end
    }

    static func valueClass(_ token: Token) -> Int? {
        switch WordKind(token.norm) {
        case .number: 0
        case .weekday, .relativeDay, .month: 1
        case nil: token.norm == "oclock" ? 0 : nil
        }
    }

    // MARK: - Self-corrections

    /// Words that can make up a correction cue, e.g. "no", "no sorry", "actually make that", "I mean".
    static let cueWords: Set<String> = ["no", "sorry", "wait", "actually", "nahi", "nahin", "matlab"]
    static let cuePhrases: [[String]] = [
        ["i", "mean"], ["make", "that"], ["make", "it"], ["or", "rather"], ["scratch", "that"],
        ["correction"], ["mera", "matlab"],
    ]
    /// Cue words that also occur in normal speech; they only count when set off by punctuation
    /// or combined with another cue ("there is no milk" is not a correction).
    static let weakCues: Set<String> = ["no", "sorry", "wait", "actually", "make that", "make it", "correction"]

    static func applyCorrections(_ input: [Token], unresolved: inout Bool) -> [Token] {
        var tokens = input
        var searchFrom = 0
        while let cue = findCue(in: tokens, from: searchFrom) {
            var sentenceStart = tokens[..<cue.start].lastIndex(where: \.endsSentence).map { $0 + 1 } ?? 0
            // ASR often ends the sentence at the hesitation: "at 3:30. Actually make it 4." —
            // the cue opens a new sentence, so the correction applies to the previous one.
            if sentenceStart == cue.start, sentenceStart > 0, !cue.isScratch {
                sentenceStart = tokens[..<(sentenceStart - 1)].lastIndex(where: \.endsSentence).map { $0 + 1 } ?? 0
            }
            let prefix = Array(tokens[sentenceStart ..< cue.start])
            let repairEnd = tokens[cue.end...].firstIndex(where: \.endsSentence).map { $0 + 1 } ?? tokens.count
            let repair = Array(tokens[cue.end ..< repairEnd])

            if cue.isScratch {
                // "scratch that" deletes what came before it in the sentence, or the previous sentence.
                var start = sentenceStart
                if prefix.isEmpty, sentenceStart > 0 {
                    start = tokens[..<(sentenceStart - 1)].lastIndex(where: \.endsSentence).map { $0 + 1 } ?? 0
                }
                tokens.removeSubrange(start ..< cue.end)
                searchFrom = start
                continue
            }
            guard !prefix.isEmpty, !repair.isEmpty,
                  let s = reparandumStart(prefix: prefix, repair: repair)
            else {
                unresolved = true
                searchFrom = cue.end
                continue
            }
            var fixed = Array(prefix[..<s]) + repair
            if s == 0, let first = fixed.first { fixed[0].raw = capitalized(first.raw) }
            if s > 0 { fixed[s - 1].raw = fixed[s - 1].bare } // drop the comma that led into the cue
            tokens.replaceSubrange(sentenceStart ..< repairEnd, with: fixed)
            searchFrom = sentenceStart
        }
        return tokens
    }

    struct Cue {
        var start: Int
        var end: Int // exclusive
        var isScratch: Bool
    }

    static func findCue(in t: [Token], from: Int) -> Cue? {
        var i = from
        while i < t.count {
            var j = i
            var parts: [String] = []
            // Greedily consume consecutive cue words/phrases: "no, sorry, I mean".
            while j < t.count {
                if let phrase = cuePhrases.first(where: { matches($0, t, at: j) }) {
                    parts.append(phrase.joined(separator: " "))
                    j += phrase.count
                } else if cueWords.contains(t[j].norm) {
                    parts.append(t[j].norm)
                    j += 1
                } else { break }
                if t[j - 1].endsSentence { break }
            }
            if !parts.isEmpty {
                let isScratch = parts.contains("scratch that")
                let setOff = (i > 0 && (t[i - 1].endsClause || t[i - 1].endsSentence)) || t[j - 1].endsClause
                let strong = parts.count > 1 || parts.contains { !weakCues.contains($0) }
                if i > 0, isScratch || strong || setOff {
                    return Cue(start: i, end: j, isScratch: isScratch)
                }
                i = j
            } else {
                i += 1
            }
        }
        return nil
    }

    static func matches(_ phrase: [String], _ t: [Token], at i: Int) -> Bool {
        guard i + phrase.count <= t.count else { return false }
        for (k, w) in phrase.enumerated() {
            if t[i + k].norm != w { return false }
            if k < phrase.count - 1, t[i + k].endsSentence { return false }
        }
        return true
    }

    /// Index in `prefix` where the part being corrected begins, or nil if unclear.
    static func reparandumStart(prefix: [Token], repair: [Token]) -> Int? {
        let head = repair[0].norm
        // 1. The repair restarts from a word already said: "to Rahul, sorry, to Priya".
        if let i = prefix.lastIndex(where: { $0.norm == head }) { return i }
        // 2. Same kind of word: numbers/times, weekdays, months, relative days.
        if let kind = WordKind(head) {
            var end = prefix.count
            while end > 0, WordKind(prefix[end - 1].norm) != kind { end -= 1 }
            if end > 0 {
                var start = end - 1
                while start > 0, WordKind(prefix[start - 1].norm) == kind { start -= 1 }
                return start
            }
        }
        // 3. The repair ends on a word already said: "meet tomorrow, no, day after tomorrow".
        if let lastWord = repair.last?.norm, let i = prefix.lastIndex(where: { $0.norm == lastWord }) {
            return i
        }
        // 4. A short repair that is a name replaces the same number of trailing words: "call John, sorry, Mike".
        if repair.count <= 2, prefix.count > repair.count, repair[0].bare.first?.isUppercase == true {
            return prefix.count - repair.count
        }
        return nil
    }

    enum WordKind: Equatable {
        case number, weekday, month, relativeDay

        init?(_ w: String) {
            if w.first?.isNumber == true || Self.numberWords.contains(w) || ["am", "pm"].contains(w) {
                self = .number
            } else if Self.weekdays.contains(w) {
                self = .weekday
            } else if Self.months.contains(w) {
                self = .month
            } else if Self.relativeDays.contains(w) {
                self = .relativeDay
            } else { return nil }
        }

        static let numberWords: Set<String> = [
            "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
            "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
            "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "million",
            "half", "quarter",
        ]
        static let weekdays: Set<String> = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        static let months: Set<String> = [
            "january", "february", "march", "april", "may", "june", "july", "august", "september",
            "october", "november", "december",
        ]
        static let relativeDays: Set<String> = ["today", "tomorrow", "tonight", "yesterday", "kal", "parso", "aaj"]
    }

    // MARK: - Rendering

    static func render(_ tokens: [Token]) -> String {
        var words = tokens.map(\.raw)
        // Re-capitalize after sentence ends and at the start.
        for i in words.indices where i == 0 || tokens[i - 1].endsSentence {
            words[i] = capitalized(words[i])
        }
        return words.joined(separator: " ")
    }

    static func capitalized(_ s: String) -> String {
        guard let f = s.first, f.isLowercase else { return s }
        return f.uppercased() + s.dropFirst()
    }
}
