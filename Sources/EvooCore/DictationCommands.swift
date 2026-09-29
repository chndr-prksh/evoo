import Foundation

/// Spoken instructions about the text, which Evoo carries out instead of typing:
///
///   "capitalize each word, the lord of the rings"  → "The Lord Of The Rings"
///   "all caps, urgent please read"                  → "URGENT PLEASE READ"
///   "lowercase, Hello World"                        → "hello world"
///   "…he said quote I'll be there end quote"        → …he said "I'll be there"
///   "…see you soon, press enter"                    → types the text, then presses Return (sends in chat apps)
///   "undo that" / "delete that" (on its own)        → undoes the last dictation (⌘Z)
public enum DictationCommands {
    public enum Casing: Equatable, Sendable {
        case title, upper, lower
    }

    public enum Action: Equatable, Sendable {
        case pressEnter
        case undo
        /// Change the text Evoo just typed ("replace Tuesday with Wednesday").
        case edit(VoiceEdit)
    }

    public struct Parsed: Equatable, Sendable {
        /// The text to process as dictation (commands removed).
        public var text: String
        /// Applied to the final text, after corrections and formatting.
        public var casing: Casing?
        public var action: Action?
    }

    static let leading: [(pattern: String, casing: Casing)] = [
        (#"(?:capitali[sz]e|capital) (?:each|every|all|the first letter of each) words?|(?:in )?title case"#, .title),
        (#"(?:all|in) caps|(?:in )?all capitals|(?:in )?upper ?case|all upper ?case"#, .upper),
        (#"(?:all |in )?lower ?case|(?:in )?small letters"#, .lower),
    ]

    public static func parse(_ input: String) -> Parsed {
        var text = input.trimmingCharacters(in: .whitespaces)
        var result = Parsed(text: text, casing: nil, action: nil)

        // A dictation that is only "undo that" / "delete that".
        if text.range(of: #"^(?i)(?:please )?(?:undo|delete|remove) (?:that|this|the last one)[.!]?$"#,
                      options: .regularExpression) != nil
        {
            return Parsed(text: "", casing: nil, action: .undo)
        }

        if let edit = VoiceEdit.parse(text) {
            return Parsed(text: "", casing: nil, action: .edit(edit))
        }

        // Leading casing command: "Capitalize each word, …" (optionally "please", optional punctuation after).
        for (pattern, casing) in leading {
            let full = #"^(?i)(?:please |can you |could you )?(?:"# + pattern + #")(?: this| the following)?[,.:;]?\s+"#
            if let r = text.range(of: full, options: .regularExpression), r.upperBound < text.endIndex {
                text = String(text[r.upperBound...])
                result.casing = casing
                break
            }
        }

        // Trailing "press enter" / "hit enter" / "press return".
        if let r = text.range(of: #"(?i)[,.;]?\s*(?:and )?(?:press|hit) (?:enter|return)[.!]?$"#, options: .regularExpression) {
            text = String(text[..<r.lowerBound])
            result.action = .pressEnter
        }

        // "quote … end quote / unquote / close quote".
        text = text.replacingOccurrences(
            of: #"(?i)[,]?\s*\b(?:open )?quote[,.]?\s+(.+?)[,.]?\s+(?:end quote|unquote|close quote)\b"#,
            with: " \"$1\"", options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)

        result.text = text
        return result
    }

    public static func applyCasing(_ casing: Casing?, to text: String) -> String {
        switch casing {
        case nil: text
        case .upper: text.uppercased()
        case .lower: text.lowercased()
        case .title:
            text.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
                guard let i = word.firstIndex(where: \.isLetter) else { return String(word) }
                return word[..<i] + word[i].uppercased() + word[word.index(after: i)...]
            }.joined(separator: " ")
        }
    }
}
