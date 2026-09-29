import Foundation

/// Voice shortcuts: say a trigger phrase, get its expansion.
///   "my email" → "chandra@example.com"; "send it to my email" → "send it to chandra@example.com"
///
/// Expansions are inserted exactly as written: they're swapped for placeholders before corrections,
/// formatting and number handling run, and restored at the end.
public struct Snippet: Codable, Equatable, Hashable, Sendable {
    public var trigger: String
    public var expansion: String

    public init(trigger: String, expansion: String) {
        self.trigger = trigger
        self.expansion = expansion
    }
}

public enum Snippets {
    public struct Masked: Sendable {
        public var text: String
        /// Placeholder → expansion.
        public var restore: [(String, String)]
        /// The whole dictation was a single trigger: insert the expansion alone, untouched.
        public var isWholeDictation: Bool
    }

    public static func mask(_ text: String, snippets: [Snippet]) -> Masked {
        var out = text
        var restore: [(String, String)] = []
        let bare = text.trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters)).lowercased()
        // Longest triggers first so "my work email" wins over "my email".
        for snippet in snippets.sorted(by: { $0.trigger.count > $1.trigger.count }) {
            let trigger = snippet.trigger.trimmingCharacters(in: .whitespaces)
            guard !trigger.isEmpty else { continue }
            if bare == trigger.lowercased() {
                return Masked(text: snippet.expansion, restore: [], isWholeDictation: true)
            }
            let pattern = #"(?i)\b"# + NSRegularExpression.escapedPattern(for: trigger) + #"\b"#
            guard out.range(of: pattern, options: .regularExpression) != nil else { continue }
            let placeholder = "evoosnippet\(restore.count)x"
            out = out.replacingOccurrences(of: pattern, with: placeholder, options: .regularExpression)
            restore.append((placeholder, snippet.expansion))
        }
        return Masked(text: out, restore: restore, isWholeDictation: false)
    }

    public static func unmask(_ text: String, _ restore: [(String, String)]) -> String {
        var out = text
        for (placeholder, expansion) in restore {
            // Casing/formatting passes may have capitalized the placeholder.
            out = out.replacingOccurrences(of: placeholder, with: expansion, options: .caseInsensitive)
        }
        return out
    }
}
