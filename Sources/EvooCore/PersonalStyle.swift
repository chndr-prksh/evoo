import Foundation

/// What Evoo typed and what the person actually sent after editing it — the raw material for learning how
/// they write (Layer 1: examples and a style summary in the polish prompt; Layer 2: fine-tuning).
public struct StylePair: Codable, Equatable, Sendable {
    public var app: String
    /// What Evoo pasted.
    public var evoo: String
    /// What was in the text box when the user moved on (sent it, or started the next dictation).
    public var sent: String
    public var date: Date

    public init(app: String, evoo: String, sent: String, date: Date = Date()) {
        self.app = app
        self.evoo = evoo
        self.sent = sent
        self.date = date
    }

    public var edited: Bool { evoo != sent }
}

/// How one person writes in one app, measured from what they sent.
public struct StyleProfile: Equatable, Sendable {
    public var app: String
    public var samples: Int
    public var lowercaseStart: Double
    public var noFinalPunctuation: Double
    public var exclamations: Double
    public var averageWords: Double
    public var contractions: Double

    /// One line for the AI, only about habits that are clear (≥ 70% of messages). nil if nothing stands out.
    public var summary: String? {
        guard samples >= 5 else { return nil }
        var traits: [String] = []
        if lowercaseStart >= 0.7 { traits.append("lowercase first letter") }
        if noFinalPunctuation >= 0.7 { traits.append("no full stop at the end") }
        if exclamations >= 0.3 { traits.append("exclamation marks") }
        if contractions >= 0.5 { traits.append("contractions like I'm, don't, gonna") }
        if averageWords <= 12 { traits.append("short messages") } else if averageWords >= 40 { traits.append("long, full paragraphs") }
        guard !traits.isEmpty else { return nil }
        return "Their style in this app: " + traits.joined(separator: ", ") + "."
    }
}

public enum PersonalStyle {
    /// Minimum edited pairs before examples are used, and how many go in a prompt.
    public static let examplesPerPrompt = 2

    /// A pair worth learning from: an edit of Evoo's text, not a different message typed afterwards.
    public static func isUsable(_ pair: StylePair) -> Bool {
        let e = pair.evoo.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = pair.sent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty, !s.isEmpty, s.count <= e.count * 2 + 20, s.count * 2 + 10 >= e.count else { return false }
        return overlap(words(e), words(s)) >= 0.5
    }

    public static func profile(app: String, pairs: [StylePair]) -> StyleProfile? {
        let sent = pairs.filter { $0.app == app }.map { $0.sent.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.suffix(200)
        guard !sent.isEmpty else { return nil }
        let n = Double(sent.count)
        func share(_ test: (String) -> Bool) -> Double { Double(sent.filter(test).count) / n }
        return StyleProfile(
            app: app, samples: sent.count,
            lowercaseStart: share { $0.first?.isLowercase == true },
            noFinalPunctuation: share { !".?!".contains($0.last ?? ".") },
            exclamations: share { $0.contains("!") },
            averageWords: Double(sent.map { $0.split(separator: " ").count }.reduce(0, +)) / n,
            contractions: share { $0.range(of: #"(?i)\b\w+'(?:m|re|s|ll|ve|d|t)\b|\bgonna\b|\bwanna\b"#, options: .regularExpression) != nil })
    }

    /// The person's edits most like `text` (same app first) — shown to the AI as "how they fix dictation".
    public static func examples(for text: String, app: String?, pairs: [StylePair], limit: Int = examplesPerPrompt)
        -> [StylePair]
    {
        let target = words(text)
        let candidates = pairs.filter { $0.edited && isUsable($0) && $0.evoo.count <= 240 }
        return candidates
            .map { pair in (pair, overlap(target, words(pair.evoo)) + (pair.app == app ? 0.3 : 0)) }
            .filter { $0.1 > 0.1 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit).map(\.0)
    }

    /// The personal part of the polish prompt: a style line and a couple of the person's own edits.
    public static func context(for text: String, app: String?, pairs: [StylePair]) -> String? {
        var lines: [String] = []
        if let app, let summary = profile(app: app, pairs: pairs)?.summary { lines.append(summary) }
        let shots = examples(for: text, app: app, pairs: pairs)
        if !shots.isEmpty {
            lines.append("Earlier dictations and what they actually sent. Keep their wording and tone; still fix mistakes, filler and self-corrections:")
            for s in shots { lines.append("Dictated: \(s.evoo)\nThey sent: \(s.sent)") }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    static func words(_ s: String) -> Set<String> {
        Set(s.lowercased().split { !($0.isLetter || $0.isNumber || $0 == "'") }.map(String.init))
    }

    static func overlap(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }
}

/// Word swaps a person keeps making to what Evoo typed, per app — "going to" → "gonna", "you" → "u",
/// deleting "please". Applied instantly (no AI) once seen at least twice and more often than not.
public struct StyleRewrite: Equatable, Sendable {
    public var from: String
    public var to: String
    public var count: Int
}

public enum StyleRewrites {
    public static let minCount = 2

    /// Learns rewrites per app from edit pairs.
    public static func learn(_ pairs: [StylePair]) -> [String: [StyleRewrite]] {
        var out: [String: [StyleRewrite]] = [:]
        for app in Set(pairs.map(\.app)) {
            let mine = pairs.filter { $0.app == app && PersonalStyle.isUsable($0) }
            var swaps: [String: [String: Int]] = [:]
            for p in mine where p.edited {
                for (a, b) in replacements(tokens(p.evoo), tokens(p.sent)) { swaps[a, default: [:]][b, default: 0] += 1 }
            }
            var rules: [StyleRewrite] = []
            for (from, targets) in swaps {
                guard let (to, n) = targets.max(by: { $0.value < $1.value }), n >= minCount else { continue }
                // Kept as it was more often than changed? Then it's not a habit.
                let kept = mine.filter { contains(tokens($0.evoo), from) && contains(tokens($0.sent), from) }.count
                guard n > kept else { continue }
                rules.append(StyleRewrite(from: from, to: to, count: n))
            }
            if !rules.isEmpty { out[app] = rules.sorted { $0.from.count > $1.from.count } } // longer phrases first
        }
        return out
    }

    public static func apply(_ text: String, rules: [StyleRewrite]) -> String {
        var out = text
        for r in rules {
            let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: r.from) + "\\b" + (r.to.isEmpty ? "\\s?" : "")
            out = out.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: r.to),
                                           options: .regularExpression)
        }
        return out.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func tokens(_ s: String) -> [String] {
        s.lowercased().split { !($0.isLetter || $0.isNumber || $0 == "'") }.map(String.init)
    }

    static func contains(_ words: [String], _ phrase: String) -> Bool {
        let p = phrase.split(separator: " ").map(String.init)
        guard !p.isEmpty, words.count >= p.count else { return false }
        return (0 ... words.count - p.count).contains { Array(words[$0 ..< $0 + p.count]) == p }
    }

    /// Changed stretches (1–3 words → 0–3 words) between two word lists, via the longest common subsequence.
    static func replacements(_ a: [String], _ b: [String]) -> [(String, String)] {
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var i = 0, j = 0, out: [(String, String)] = []
        var da: [String] = [], db: [String] = []
        func flush() {
            if !da.isEmpty, da.count <= 3, db.count <= 3, da != db { out.append((da.joined(separator: " "), db.joined(separator: " "))) }
            da = []; db = []
        }
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] { flush(); i += 1; j += 1 }
            else if j < b.count, i == a.count || dp[i][j + 1] >= dp[i + 1][j] { db.append(b[j]); j += 1 }
            else { da.append(a[i]); i += 1 }
        }
        flush()
        return out
    }
}
