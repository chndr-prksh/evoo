import Foundation

/// Learns from how the user edits what Evoo typed, so it adapts over time:
///  • names and terms they correct ("Deva" → "Divya") join the personal dictionary;
///  • per-app habits: e.g. always deleting the final full stop in WhatsApp, or lowercasing the first letter.
/// Only the counts and learned words are kept — never the text itself.
public enum EditLearner {
    public enum Lesson: Equatable, Sendable {
        /// The user replaced a word Evoo typed.
        case word(heard: String, meant: String)
        /// Observations of the final full stop: kept (false) or deleted (true).
        case finalPeriod(dropped: Bool)
        /// Observations of the first letter: kept capitalized (false) or lowercased (true).
        case firstLetter(lowered: Bool)
    }

    /// Compares what Evoo inserted with what the text looks like after the user's edits.
    /// Text the user added after the dictation is ignored. Returns nothing if they rewrote it entirely.
    public static func lessons(inserted: String, edited: String) -> [Lesson] {
        let a = words(inserted), b = words(edited)
        guard !a.isEmpty, !b.isEmpty else { return [] }
        let pairs = align(a.map(bare), b.map(bare))
        let matched = pairs.filter { $0.0 != nil && $0.1 != nil && bare(a[$0.0!]).lowercased() == bare(b[$0.1!]).lowercased() }
        guard Double(matched.count) >= Double(a.count) * 0.5 else { return [] } // rewritten, not edited

        var lessons: [Lesson] = []
        // Word substitutions: a run of exactly one deleted and one inserted word between matches.
        var i = 0
        while i < pairs.count {
            if let x = pairs[i].0, pairs[i].1 == nil, i + 1 < pairs.count, pairs[i + 1].0 == nil, let y = pairs[i + 1].1,
               (i + 2 == pairs.count || pairs[i + 2].0 != nil)
            {
                lessons.append(.word(heard: bare(a[x]), meant: bare(b[y])))
                i += 2
                continue
            }
            if let x = pairs[i].0, let y = pairs[i].1, bare(a[x]) != bare(b[y]), bare(a[x]).lowercased() == bare(b[y]).lowercased(), x > 0 {
                lessons.append(.word(heard: bare(a[x]), meant: bare(b[y]))) // casing fix mid-sentence ("divya" → "Divya")
            }
            i += 1
        }

        // Final full stop: only judged if the last word Evoo typed is still there.
        if inserted.hasSuffix("."), let lastA = a.indices.last,
           let pair = pairs.first(where: { $0.0 == lastA }), let y = pair.1
        {
            lessons.append(.finalPeriod(dropped: !b[y].hasSuffix(".")))
        }
        // First letter: only if the first word is still the same word.
        if let first = pairs.first(where: { $0.0 == 0 }), let y = first.1,
           bare(a[0]).lowercased() == bare(b[y]).lowercased(), a[0].first?.isUppercase == true, a[0] != "I"
        {
            lessons.append(.firstLetter(lowered: b[y].first?.isLowercase == true))
        }
        return lessons
    }

    static func words(_ s: String) -> [String] { s.split(whereSeparator: \.isWhitespace).map(String.init) }

    static func bare(_ w: String) -> String {
        w.trimmingCharacters(in: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'-")))
    }

    /// Longest-common-subsequence alignment (case-insensitive). Unmatched words appear as (i, nil) / (nil, j).
    static func align(_ a: [String], _ b: [String]) -> [(Int?, Int?)] {
        let la = a.map { $0.lowercased() }, lb = b.map { $0.lowercased() }
        var dp = Array(repeating: Array(repeating: 0, count: lb.count + 1), count: la.count + 1)
        for i in stride(from: la.count - 1, through: 0, by: -1) {
            for j in stride(from: lb.count - 1, through: 0, by: -1) {
                dp[i][j] = la[i] == lb[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var out: [(Int?, Int?)] = []
        var i = 0, j = 0
        while i < la.count, j < lb.count {
            if la[i] == lb[j] { out.append((i, j)); i += 1; j += 1 }
            else if dp[i + 1][j] >= dp[i][j + 1] { out.append((i, nil)); i += 1 }
            else { out.append((nil, j)); j += 1 }
        }
        while i < la.count { out.append((i, nil)); i += 1 }
        // Words the user added after the dictation are not edits of it.
        return out
    }
}

/// What Evoo has learned about the user's habits, per app. Stored as counts only.
public struct LearnedHabits: Codable, Equatable, Sendable {
    public struct AppHabits: Codable, Equatable, Sendable {
        public var periodsKept = 0
        public var periodsDropped = 0
        public var capitalsKept = 0
        public var capitalsLowered = 0

        /// Drop the final full stop once the user has done it at least twice and clearly more often than not.
        public var dropsFinalPeriod: Bool { periodsDropped >= 2 && Double(periodsDropped) >= Double(periodsKept) * 2 }
        public var lowercasesStart: Bool { capitalsLowered >= 2 && Double(capitalsLowered) >= Double(capitalsKept) * 2 }
    }

    public var apps: [String: AppHabits] = [:]

    public init() {}

    public mutating func record(_ lessons: [EditLearner.Lesson], app: String) {
        var h = apps[app] ?? AppHabits()
        for lesson in lessons {
            switch lesson {
            case let .finalPeriod(dropped): if dropped { h.periodsDropped += 1 } else { h.periodsKept += 1 }
            case let .firstLetter(lowered): if lowered { h.capitalsLowered += 1 } else { h.capitalsKept += 1 }
            case .word: break
            }
        }
        apps[app] = h
    }

    /// Applies the app's learned habits to text about to be typed.
    public func adapt(_ text: String, app: String?, isName: (String) -> Bool) -> String {
        guard let app, let h = apps[app] else { return text }
        var out = text
        if h.dropsFinalPeriod, out.hasSuffix("."), !out.hasSuffix(".."), !out.contains("\n") {
            out.removeLast()
        }
        if h.lowercasesStart, let first = out.split(separator: " ").first.map(String.init),
           first != "I", !first.hasPrefix("I'"), !isName(first), let c = out.first, c.isUppercase
        {
            out = c.lowercased() + out.dropFirst()
        }
        return out
    }
}
