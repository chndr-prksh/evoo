import Foundation

/// Names worth recognizing in the current dictation, harvested from what's on screen
/// (chat header, email recipients, the text around the cursor). The same idea as Wispr Flow's
/// "Context Awareness", done locally: the terms only live for one dictation.
public enum ContextVocabulary {
    /// Extracts likely proper nouns: capitalized words that aren't ordinary English words
    /// ("Divya", "Kubernetes", "Priyanka"), plus CamelCase / acronym terms ("GitHub", "OKR").
    public static func names(from texts: [String], isKnownWord: (String) -> Bool, limit: Int = 150) -> [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for text in texts {
            for raw in text.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "-" }) {
                let word = raw.trimmingCharacters(in: CharacterSet(charactersIn: "'-"))
                guard word.count >= 3, word.count <= 24, let first = word.first, first.isUppercase,
                      word.allSatisfy({ $0.isLetter && $0.isASCII || $0 == "-" || $0 == "'" }) else { continue }
                let lower = word.lowercased()
                let isAcronymOrCamel = word.dropFirst().contains(where: \.isUppercase)
                guard isAcronymOrCamel || !PersonalDictionary.isKnown(lower, isKnownWord) else { continue }
                if counts[word] == nil { order.append(word) }
                counts[word, default: 0] += 1
            }
        }
        // Most frequent first, so the chat's own participants win over one-off words.
        return order.sorted { counts[$0]! > counts[$1]! }.prefix(limit).map { $0 }
    }
}
