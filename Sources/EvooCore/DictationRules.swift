import Foundation
import NaturalLanguage

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
        var tokens = removeCommaFillers(normalizeMeridiem(input)).split(whereSeparator: \.isWhitespace)
            .map { Token(String($0)) }
        tokens = removeFillers(tokens)
        tokens = removeStutters(tokens)
        tokens = collapseValueCorrections(tokens)
        tokens = collapseEchoNegations(tokens)
        tokens = collapseRestatements(tokens)
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

    /// Spoken fillers the speech model sets off with commas: "…to, like, give…", "You know, we…", "So yeah, …".
    /// With commas around them they're fillers; without, they're words ("I like it", "you know the answer").
    /// ("I mean" isn't here: it's a correction cue.) Measured: the 1.7B polish model left these in.
    public static func removeCommaFillers(_ text: String) -> String {
        let fillers = "(?:like|you know|basically|so yeah|so basically|kind of|sort of|literally|okay so)"
        var out = text
        // Mid-sentence: "…to, like, give…" → "…to give…"
        // Between clauses ("…last night, you know, we still…") the comma stays; inside a clause it goes.
        out = out.replacingOccurrences(of: "(?i),\\s*(?:you know|so basically|basically|so yeah|okay so),\\s*", with: ", ",
                                       options: .regularExpression)
        out = out.replacingOccurrences(of: "(?i),\\s*" + fillers + ",\\s*", with: " ", options: .regularExpression)
        // "You know we still need…" / "…the report, you know." — "you know" leading into a sentence, or trailing it.
        if let lead = try? NSRegularExpression(pattern: "(?i)(^|[.!?]\\s+)you know,?\\s+((?:we|i|they|he|she|there|so|my|our)\\b)") {
            for m in lead.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
                guard let r = Range(m.range, in: out), let a = Range(m.range(at: 1), in: out),
                      let b = Range(m.range(at: 2), in: out) else { continue }
                let next = String(out[b])
                out.replaceSubrange(r, with: String(out[a]) + next.prefix(1).uppercased() + next.dropFirst())
            }
        }
        out = out.replacingOccurrences(of: "(?i),\\s*you know(?=[.!?]|$)", with: "", options: .regularExpression)
        // "…to like give you…" → "…to give you…" ("I'd like to" keeps its "like").
        if let re = try? NSRegularExpression(pattern: "(?i)\\bto like (\\w+)") {
            for m in re.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
                guard let r = Range(m.range, in: out), let w = Range(m.range(at: 1), in: out),
                      DictationFormatter.isVerb(String(out[w])) else { continue }
                out.replaceSubrange(r, with: "to " + out[w])
            }
        }
        // Sentence start: "Like, engineering…" → "Engineering…"
        guard let re = try? NSRegularExpression(pattern: "(?i)(^|[.!?]\\s+)" + fillers + ",?\\s+(\\w)") else { return out }
        for m in re.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
            guard let whole = Range(m.range, in: out), let lead = Range(m.range(at: 1), in: out),
                  let first = Range(m.range(at: 2), in: out) else { continue }
            // Only when a comma marked it as a filler, or it's a two-word filler ("So basically …").
            let matched = String(out[whole])
            guard matched.contains(",") || matched.lowercased().contains("so ") else { continue }
            out.replaceSubrange(whole, with: String(out[lead]) + out[first].uppercased())
        }
        return out
    }

    /// Small words a comma never really follows ("to, Wednesday").
    static let glueWords: Set<String> = ["to", "the", "a", "an", "and", "of", "on", "in", "at", "for", "from", "with",
                                         "is", "was", "are", "be", "my", "your", "our", "their", "his", "her", "by"]
    static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "uhm", "erm", "er", "hmm", "mm", "mhm", "ah"]

    static func removeFillers(_ tokens: [Token]) -> [Token] {
        var out: [Token] = []
        for (i, t) in tokens.enumerated() {
            // "Um, so, uh, I think…": a "so" wedged between fillers is a filler too.
            let isFiller = fillers.contains(t.norm) || (t.norm == "so" && t.raw.hasSuffix(",")
                && (i > 0 && fillers.contains(tokens[i - 1].norm) || i + 1 < tokens.count && fillers.contains(tokens[i + 1].norm)))
            if isFiller {
                // "to, um, Wednesday" → "to Wednesday": the comma only framed the filler.
                if t.endsClause, var last = out.last, last.endsClause, glueWords.contains(last.norm) {
                    last.raw = last.bare
                    out[out.count - 1] = last
                }
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

    /// Real one- and two-letter words, so only broken-off starts are dropped.
    static let shortWords: Set<String> = ["a", "i", "an", "am", "as", "at", "be", "by", "do", "go", "he", "hi", "if",
                                          "in", "is", "it", "me", "my", "no", "of", "oh", "ok", "on", "or", "so", "to",
                                          "up", "us", "we", "ah", "ha", "yo"]

    /// Common three-letter words, which are never treated as broken-off starts ("the theory", "car carpet").
    static let commonThreeLetter: Set<String> = [
        "the", "and", "for", "you", "are", "but", "not", "all", "any", "can", "had", "her", "was", "one", "our",
        "out", "day", "get", "has", "him", "his", "how", "man", "new", "now", "old", "see", "two", "way", "who",
        "did", "its", "let", "put", "say", "she", "too", "use", "car", "cat", "dog", "big", "bad", "yes", "yet",
        "got", "may", "run", "sit", "top", "red", "far", "few", "own", "off", "end", "why", "ask", "men", "per",
        "art", "pay", "buy", "fun", "job", "law", "map", "sun", "war", "air", "age", "key", "low", "set", "try",
    ]

    static func removeStutters(_ tokens: [Token]) -> [Token] {
        // Broken-off word starts: "like m make it" → "like make it", "your dis dictionary" → "your dictionary".
        var t = tokens.enumerated().filter { i, tok in
            guard i + 1 < tokens.count, !tok.endsClause, !tok.endsSentence else { return true }
            let w = tok.norm, next = tokens[i + 1].norm
            guard !w.isEmpty, w.allSatisfy(\.isLetter), next.first == w.first else { return true }
            // The fragment is the word's start, or nearly ("dis" before "dictionary").
            let head = String(next.prefix(w.count))
            let mismatches = zip(head, w).filter { $0 != $1 }.count
            let fragment = (w.count <= 2 && next.hasPrefix(w) && !shortWords.contains(w) && next.count > w.count)
                || (w.count == 3 && mismatches <= 1 && !commonThreeLetter.contains(w) && next.count >= 6)
            return !fragment
        }.map(\.element)
        t = removeRestarts(t)
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

    /// Openers people restart with ("if it sounds… if it's unusual", "when we… when we're done").
    static let restartOpeners: Set<String> = ["if", "when", "i", "we", "you", "it", "so", "and", "but", "because",
                                              "the", "this", "that", "they", "he", "she", "there", "what", "can"]

    /// A phrase started, abandoned, and started again with a slightly different word:
    /// "if it sounds if it's unusual" → "if it's unusual".
    static func removeRestarts(_ input: [Token]) -> [Token] {
        var t = input
        var i = 0
        while i + 3 < t.count {
            let a = t[i].norm, b = t[i + 1].norm
            guard restartOpeners.contains(a) else { i += 1; continue }
            var restarted = false
            for j in (i + 2) ... min(i + 5, t.count - 2) {
                guard t[j].norm == a, t[j + 1].norm != b, t[j + 1].norm.hasPrefix(b), b.count >= 2 else { continue }
                // Nothing between the two starts may end a clause — that would be two real phrases.
                guard !t[i ..< j].contains(where: { $0.endsClause || $0.endsSentence }) else { break }
                t.removeSubrange(i ..< j)
                restarted = true
                break
            }
            if !restarted { i += 1 }
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
                guard let next = valueGroup(in: t, at: k), groupClass(t, next) == groupClass(t, first) else { break }
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

    /// Multi-word dates: "day after tomorrow", "next week", "this Friday", "the weekend".
    static let datePhrases: [[String]] = [
        ["day", "after", "tomorrow"], ["day", "before", "yesterday"], ["the", "day", "after"],
        ["the", "week", "after"], ["the", "week", "after", "next"],
        ["next", "week"], ["this", "week"], ["next", "month"], ["this", "month"], ["next", "year"],
        ["this", "weekend"], ["next", "weekend"], ["the", "weekend"], ["tomorrow", "morning"],
        ["tomorrow", "evening"], ["tomorrow", "night"], ["tonight"], ["this", "evening"], ["this", "morning"],
    ]
    static let weekdayPrefixes: Set<String> = ["next", "this", "coming", "last"]

    /// A run of tokens forming one value: "4 PM", "3:30", "five thirty", "Tuesday", "day after tomorrow".
    static func valueGroup(in t: [Token], at i: Int) -> Range<Int>? {
        guard i < t.count else { return nil }
        if let phrase = datePhrases.filter({ matches($0, t, at: i) }).max(by: { $0.count < $1.count }) {
            return i ..< i + phrase.count
        }
        if weekdayPrefixes.contains(t[i].norm), i + 1 < t.count, WordKind(t[i + 1].norm) == .weekday,
           !t[i].endsClause
        {
            return i ..< i + 2 // "next Monday"
        }
        guard let cls = valueClass(t[i]) else { return nil }
        var end = i + 1
        // A group ends at punctuation or after AM/PM ("4 PM 5 PM" is two times).
        while end < t.count, !t[end - 1].endsClause, !t[end - 1].endsSentence,
              !["am", "pm"].contains(t[end - 1].norm), valueClass(t[end]) == cls { end += 1 }
        return i ..< end
    }

    static func groupClass(_ t: [Token], _ group: Range<Int>) -> Int? {
        group.count > 1 && t[group].contains(where: { valueClass($0) == 1 || ["day", "week", "weekend", "month", "year", "morning", "evening", "night"].contains($0.norm) })
            ? 1 : valueClass(t[group.lowerBound])
    }

    /// "…play tomorrow, not tomorrow, day after tomorrow" / "send it to John, not John, Mike":
    /// the speaker repeats what they're taking back after "not", then says the replacement.
    static func collapseEchoNegations(_ input: [Token]) -> [Token] {
        var t = input
        var i = 1
        while i < t.count {
            // "to be or not to be", "whether or not", "like it or not" aren't corrections.
            guard t[i].norm == "not", !t[i - 1].endsSentence, t[i - 1].norm != "or" else { i += 1; continue }
            var echoed = 0
            for k in stride(from: min(3, i), through: 1, by: -1) where i + k < t.count {
                let before = t[(i - k) ..< i].map(\.norm), after = t[(i + 1) ... (i + k)].map(\.norm)
                if before == after { echoed = k; break }
            }
            var start = i - echoed
            // Partial echo: "2 laptops, not 2, 3 laptops" repeats only the first word of what's taken back.
            // Only after a pause ("2 laptops, not 2, …"): without one it's ordinary speech.
            if echoed == 0, i + 1 < t.count, t[i - 1].raw.hasSuffix(","),
               let j = (max(0, i - 3) ..< i).last(where: { t[$0].norm == t[i + 1].norm })
            {
                echoed = 1
                start = j
            }
            let restStart = i + 1 + echoed
            // Needs a replacement after the echo, in the same sentence: "not tomorrow, <day after tomorrow>".
            guard echoed > 0, restStart < t.count, !t[restStart - 1].endsSentence else { i += 1; continue }
            t.removeSubrange(start ..< restStart)
            if start > 0 { t[start - 1].raw = t[start - 1].bare } // drop a comma left dangling
            i = start + 1
        }
        return t
    }

    static let intensifiers: Set<String> = ["very", "really", "so", "super", "extremely", "quite", "too", "pretty",
                                            "totally", "absolutely", "completely", "much", "way"]
    /// Words that may sit between a word and its restatement: "bad, not no bad, very bad".
    static let restatementFillers: Set<String> = intensifiers.union(["not", "no", "i", "mean", "sorry", "actually",
                                                                    "like", "or", "rather"])

    /// A word said again with a sharper modifier replaces the first attempt:
    ///   "It's still bad, very bad"               → "It's still very bad"
    ///   "The dictation is still bad, not no bad, very bad" → "The dictation is still very bad"
    static func collapseRestatements(_ input: [Token]) -> [Token] {
        var t = input
        var changed = true
        while changed {
            changed = false
            for i in t.indices {
                let w = t[i].norm
                guard !w.isEmpty, !functionWords.contains(w), !restatementFillers.contains(w), !t[i].endsSentence
                else { continue }
                // The same word again within 5 words, with only fillers in between.
                guard let j = (i + 1 ..< min(t.count, i + 6)).first(where: { t[$0].norm == w }),
                      t[(i + 1) ..< j].allSatisfy({ restatementFillers.contains($0.norm) }), j > i + 1
                else { continue }
                // Keep the modifiers directly before the restated word ("very"), drop the rest.
                var keepFrom = j
                while keepFrom > i + 1, intensifiers.contains(t[keepFrom - 1].norm), !t[keepFrom - 1].endsClause {
                    keepFrom -= 1
                }
                guard keepFrom < j || t[(i + 1) ..< j].contains(where: { !intensifiers.contains($0.norm) }) else { continue }
                t.removeSubrange(i ..< keepFrom)
                changed = true
                break
            }
        }
        return t
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
            guard !prefix.isEmpty, !repair.isEmpty, let plan = plan(prefix: prefix, repair: repair) else {
                unresolved = true
                searchFrom = cue.end
                continue
            }
            var fixed: [Token]
            switch plan {
            case let .truncate(s, unit):
                var body = repair
                if !unit.isEmpty, var last = body.popLast() {
                    // "5." + ["boxes"] → "5 boxes."
                    let end = last.trailingPunctuation
                    last.raw = last.bare
                    body += [last] + unit.map { Token($0) }
                    body[body.count - 1].raw += end
                }
                fixed = Array(prefix[..<s]) + body
                if s == 0, let first = fixed.first { fixed[0].raw = capitalized(first.raw) }
                if s > 0 { fixed[s - 1].raw = fixed[s - 1].bare } // drop the comma that led into the cue
            case let .swap(i):
                fixed = prefix
                let tail = fixed[i].trailingPunctuation
                fixed.replaceSubrange(i ... i, with: repair.map { Token($0.bare) })
                fixed[i + repair.count - 1].raw += tail
                // The sentence's end moves from the repair to the (unchanged) prefix.
                let end = repair.last?.trailingPunctuation ?? ""
                fixed[fixed.count - 1].raw = fixed[fixed.count - 1].bare + end
            }
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

    /// How to apply a correction to the words before the cue.
    enum Plan: Equatable {
        /// Drop everything from `at` and continue with the repair; `unit` words said after the old
        /// value are kept ("Order 3 boxes, actually 5" → "Order 5 boxes").
        case truncate(at: Int, unit: [String] = [])
        /// Replace the word at `index` in place ("CC Tom on the email, I mean Tim" → "CC Tim on the email").
        case swap(index: Int)
    }

    static let determiners: Set<String> = ["a", "an", "the", "this", "that", "my", "your", "our", "their", "his",
                                           "her", "next", "last"]
    static let functionWords: Set<String> = ["him", "her", "it", "them", "me", "you", "us", "the", "a", "an", "to",
                                             "of", "in", "on", "at", "for", "and", "or", "is", "was"]
    /// A sentence that stops on one of these was abandoned mid-thought ("I think we should, actually…").
    static let danglingEnds: Set<String> = ["should", "could", "would", "will", "can", "might", "must", "to", "the",
                                            "a", "an", "and", "but", "or", "so", "gonna", "wanna", "we", "i", "just"]

    static func plan(prefix: [Token], repair: [Token]) -> Plan? {
        let head = repair[0].norm
        // 1. The repair restarts from a word already said: "to Rahul, sorry, to Priya".
        if let i = prefix.lastIndex(where: { $0.norm == head }) { return .truncate(at: i) }
        // 2. Same kind of value: numbers/times, weekdays, months, relative days.
        if let kind = WordKind(head) {
            var end = prefix.count
            while end > 0, WordKind(prefix[end - 1].norm) != kind { end -= 1 }
            if end > 0 {
                var start = end - 1
                while start > 0, WordKind(prefix[start - 1].norm) == kind { start -= 1 }
                // A bare new value keeps the old value's unit: "3 boxes, actually 5" → "5 boxes".
                let bareValue = repair.allSatisfy { WordKind($0.norm) == kind }
                let unit = bareValue ? prefix[end...].map(\.bare).filter { !$0.isEmpty } : []
                return .truncate(at: start, unit: unit.count <= 2 ? unit : [])
            }
        }
        // 3. Restart from an article: "a 7 out of 10, actually an 8", "next week, no, the week after".
        if determiners.contains(head), let i = prefix.lastIndex(where: { determiners.contains($0.norm) }) {
            return .truncate(at: i)
        }
        // 4. A new action replaces the old one: "Email him, no, call him" → "Call him".
        if startsWithVerb(repair), startsWithVerb(prefix) || startsWithVerb(prefix, asInstruction: true) {
            return .truncate(at: 0)
        }
        // 5. The first attempt was abandoned mid-phrase: "I think we should, actually let's ship it".
        if let last = prefix.last, danglingEnds.contains(last.norm) { return .truncate(at: 0) }
        // 6. A name replaces a name: "CC Tom on the email, I mean Tim", "Call John, sorry, Mike".
        if repair.count <= 2, repair.allSatisfy({ $0.bare.first?.isUppercase == true }),
           let i = prefix.indices.dropFirst().last(where: {
               prefix[$0].bare.first?.isUppercase == true && prefix[$0].norm != "i" && WordKind(prefix[$0].norm) == nil
           })
        {
            return .swap(index: i)
        }
        // 7. The repair ends on a content word already said: "meet tomorrow, no, day after tomorrow".
        if let lastWord = repair.last?.norm, !functionWords.contains(lastWord),
           let i = prefix.lastIndex(where: { $0.norm == lastWord })
        {
            return .truncate(at: i)
        }
        // 8. A one-word repair replaces the last word: "Buy apples, no, oranges", "blue, actually green".
        //    Never a pronoun: "I love you, I mean it" is not a correction.
        if repair.count == 1, prefix.count > 1, !functionWords.contains(head) { return .truncate(at: prefix.count - 1) }
        return nil
    }

    /// Whether the phrase opens with a verb. `asInstruction` reads it after "to" ("to email him"),
    /// which settles words like "email" that the tagger otherwise calls nouns.
    static func startsWithVerb(_ tokens: [Token], asInstruction: Bool = false) -> Bool {
        let phrase = tokens.prefix(4).map(\.bare).joined(separator: " ").lowercased()
        guard !phrase.isEmpty, !functionWords.contains(tokens[0].norm) else { return false }
        let text = asInstruction ? "to " + phrase : phrase
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let first = asInstruction ? text.index(text.startIndex, offsetBy: 3) : text.startIndex
        return tagger.tag(at: first, unit: .word, scheme: .lexicalClass).0 == .verb
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
            "half", "quarter", "noon", "midnight",
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
