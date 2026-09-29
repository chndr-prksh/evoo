import Foundation

/// Edits to the text Evoo just typed, spoken as a dictation of their own:
///   "replace Tuesday with Wednesday", "change 5 PM to 6 PM"
///   "delete the last sentence", "delete the last word"
///   "make that a list", "make that a numbered list"
public enum VoiceEdit: Equatable, Sendable {
    case replace(old: String, new: String)
    case deleteLastSentence
    case deleteLastWord
    case makeList(numbered: Bool)

    /// Only a dictation that is entirely an edit command counts ("replace the old logo" in a sentence doesn't).
    public static func parse(_ dictation: String) -> VoiceEdit? {
        let s = dictation.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".!?")))
        func match(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: "^(?i)" + pattern + "$"),
                  let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
            return (0 ..< m.numberOfRanges).map { i in
                Range(m.range(at: i), in: s).map { String(s[$0]) } ?? ""
            }
        }
        if let m = match(#"(?:replace|change) ["“]?(.+?)["”]?,? (?:with|to) ["“]?(.+?)["”]?"#) {
            return .replace(old: m[1], new: m[2])
        }
        if match(#"(?:delete|remove|scratch) (?:the )?last sentence"#) != nil { return .deleteLastSentence }
        if match(#"(?:delete|remove) (?:the )?last word"#) != nil { return .deleteLastWord }
        if let m = match(#"(?:make|turn|format) (?:that|this|it) (?:into )?(?:a |an )?(numbered |bulleted |bullet )?(?:list|bullets|bullet points)"#) {
            return .makeList(numbered: m[1].lowercased().hasPrefix("numbered"))
        }
        return nil
    }

    /// The edited version of `text`, or nil if the edit doesn't apply (e.g. the word isn't there).
    public func apply(to text: String, style: OutputStyle) -> String? {
        switch self {
        case let .replace(old, new):
            guard let r = text.range(of: old, options: [.caseInsensitive, .backwards]) else { return nil }
            var replacement = new
            // Keep the original's capitalization at the start of a word ("Tuesday" → "Wednesday").
            if text[r].first?.isUppercase == true, let f = replacement.first {
                replacement = f.uppercased() + replacement.dropFirst()
            }
            return text.replacingCharacters(in: r, with: replacement)

        case .deleteLastSentence:
            let sentences = DictationFormatter.splitSentences(text)
            return sentences.dropLast().joined(separator: " ")

        case .deleteLastWord:
            var words = text.split(separator: " ").map(String.init)
            guard let last = words.popLast() else { return nil }
            let ending = String(last.reversed().prefix { ".?!".contains($0) }.reversed())
            guard !words.isEmpty else { return "" }
            words[words.count - 1] = words[words.count - 1].trimmingCharacters(in: CharacterSet(charactersIn: ",;:")) + ending
            return words.joined(separator: " ")

        case let .makeList(numbered):
            var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            var intro = ""
            if let colon = body.firstIndex(of: ":") {
                intro = String(body[...colon])
                body = String(body[body.index(after: colon)...])
            } else if let e = DictationFormatter.parseEnumeration(body) {
                intro = e.intro.isEmpty ? "" : e.intro + ":"
                body = e.items.joined(separator: ", ")
            }
            let items = body.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
                .replacingOccurrences(of: #",?\s+(?:and|or)\s+"#, with: ", ", options: .regularExpression)
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard items.count >= 2 else { return nil }
            let lines = items.enumerated().map { i, item in
                (numbered ? "\(i + 1). " : style.bullet) + DictationFormatter.capitalizeFirst(item)
            }
            return (intro.isEmpty ? "" : intro + "\n") + lines.joined(separator: "\n")
        }
    }
}
