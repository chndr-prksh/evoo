import Foundation

/// Names worth recognizing in the current dictation, harvested from what's on screen
/// (chat header, email recipients, the text around the cursor). The same idea as Wispr Flow's
/// "Context Awareness", done locally: the terms only live for one dictation.
public enum ContextVocabulary {
    /// Extracts likely proper nouns: capitalized words that aren't ordinary English words
    /// ("Divya", "Kubernetes", "Priyanka"), plus CamelCase / acronym terms ("GitHub", "OKR").
    /// Extracts likely proper nouns and unusual terms: capitalized words that aren't ordinary English words
    /// ("Divya", "Kubernetes"), CamelCase/acronyms ("GitHub", "OKR"), and unusual lowercase words that appear
    /// at least twice ("evoo", "kubectl") — never ordinary words, however they're capitalized ("HOW ARE YOU?").
    public static func names(from texts: [String], isKnownWord: (String) -> Bool, limit: Int = 150) -> [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for text in texts {
            for raw in text.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "-" }) {
                let word = raw.trimmingCharacters(in: CharacterSet(charactersIn: "'-"))
                guard word.count >= 3, word.count <= 24,
                      word.allSatisfy({ $0.isLetter && $0.isASCII || $0 == "-" || $0 == "'" }),
                      !PersonalDictionary.isKnown(word.lowercased(), isKnownWord) else { continue }
                if counts[word] == nil { order.append(word) }
                counts[word, default: 0] += 1
            }
        }
        let kept = order.filter { w in
            w.first!.isUppercase || (w.count >= 4 && counts[w]! >= 2) // lowercase needs to be repeated
        }
        // Most frequent first, so the chat's own participants win over one-off words.
        return kept.sorted { counts[$0]! > counts[$1]! }.prefix(limit).map { $0 }
    }
}

/// Unusual words Evoo keeps seeing on your screen, remembered across dictations. A word seen in several
/// separate dictations joins the personal dictionary for good — that's how it learns your world (colleagues,
/// products, projects) without you typing anything. Only the words and counts are stored, never the screen.
public struct ScreenLexicon: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var sessions: Int
        public var lastSeen: Date
    }

    public var words: [String: Entry] = [:]
    /// Dictations a word must appear in before it's learned.
    public static let threshold = 3
    static let capacity = 3_000

    public init() {}

    /// Records one dictation's screen words; returns those that just reached the threshold.
    public mutating func observe(_ seen: [String], at date: Date = Date()) -> [String] {
        var promoted: [String] = []
        for word in Set(seen) {
            var entry = words[word] ?? Entry(sessions: 0, lastSeen: date)
            entry.sessions += 1
            entry.lastSeen = date
            words[word] = entry
            if entry.sessions == Self.threshold { promoted.append(word) }
        }
        if words.count > Self.capacity { // forget the stalest
            for (word, _) in words.sorted(by: { $0.value.lastSeen < $1.value.lastSeen }).prefix(words.count - Self.capacity) {
                words[word] = nil
            }
        }
        return promoted.sorted()
    }
}
