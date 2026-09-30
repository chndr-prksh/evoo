import Foundation
import NaturalLanguage

/// How lists and line breaks should be written for the app receiving the text.
public enum OutputStyle: String, Sendable, CaseIterable, Codable {
    /// Markdown-aware apps (Notion, Obsidian, editors, browsers): "- item", "1. item", "- [ ] task".
    case markdown
    /// Everything else (Mail, Notes, Messages, Slack, Word): "• item", "1. item", "☐ task".
    case plain
    /// Terminals: never insert line breaks — a pasted newline can run a command.
    case singleLine

    /// Picks a style from the frontmost app's bundle identifier.
    public static func forApp(_ bundleID: String?) -> OutputStyle {
        guard let id = bundleID?.lowercased() else { return .plain }
        if terminals.contains(where: id.hasPrefix) { return .singleLine }
        if markdownApps.contains(where: id.hasPrefix) { return .markdown }
        return .plain
    }

    static let terminals = [
        "com.apple.terminal", "com.googlecode.iterm2", "dev.warp.", "net.kovidgoyal.kitty", "io.alacritty",
        "com.mitchellh.ghostty", "co.zeit.hyper", "com.github.wez.wezterm",
    ]
    static let markdownApps = [
        "notion.id", "md.obsidian", "com.microsoft.vscode", "com.todesktop.230313mzl4w4u92", // Cursor
        "dev.zed.zed", "com.jetbrains.", "com.sublimetext.", "com.google.chrome", "com.apple.safari",
        "org.mozilla.firefox", "company.thebrowser.", "com.microsoft.edgemac", "com.brave.browser",
        "com.openai.chat", "com.anthropic.claudefordesktop", "com.github.", "com.linear", "com.bear-writer",
    ]

    var bullet: String { self == .markdown ? "- " : "• " }
    var checkbox: String { self == .markdown ? "- [ ] " : "☐ " }
}

/// Lightweight formatting from how people naturally dictate. Deterministic and fast (< 1 ms).
///
///  • spoken commands: "new line", "new paragraph", "bullet point"
///  • bulleted lists:  "…I want to buy tomorrow bread, eggs, milk and apples" → intro + one item per line
///  • numbered lists:  "first run the tests, second build, third deploy" / "step one … step two …"
///  • checklists:      "my to-do list: call the bank, pay rent, book tickets"
///  • emails:          "chandra at gmail.com" → "chandra@gmail.com"
public enum DictationFormatter {
    public static func format(_ input: String, style: OutputStyle) -> String {
        var text = spokenCommands(input, style: style)
        text = emails(text)
        guard style != .singleLine else { return text }
        let paragraphs = text.components(separatedBy: "\n").map { line -> String in
            if let numbered = numberedList(line, style: style) { return numbered }
            if let bulleted = bulletedList(line, style: style) { return bulleted }
            return line
        }
        return paragraphs.joined(separator: "\n")
    }

    // MARK: - Spoken commands

    static func spokenCommands(_ text: String, style: OutputStyle) -> String {
        let breakFor: [(pattern: String, replacement: String)] = [
            (#"(?i)[,.;]?\s*\b(?:new|next) paragraph\b[,.;:]?\s*"#, style == .singleLine ? " " : "\n\n"),
            (#"(?i)[,.;]?\s*\bnew line\b[,.;:]?\s*"#, style == .singleLine ? " " : "\n"),
            (#"(?i)[,.;]?\s*\b(?:new |next )?bullet(?: point)?\b[,.;:]?\s*"#, style == .singleLine ? ", " : "\n" + style.bullet),
        ]
        var out = text
        for (pattern, replacement) in breakFor {
            out = out.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        // Capitalize the first letter after each inserted break.
        var chars = Array(out)
        var capitalizeNext = true
        for i in chars.indices {
            if chars[i] == "\n" { capitalizeNext = true; continue }
            if capitalizeNext, chars[i].isLetter {
                chars[i] = Character(chars[i].uppercased())
                capitalizeNext = false
            } else if capitalizeNext, !chars[i].isWhitespace, !"-•☐[]".contains(chars[i]) {
                capitalizeNext = false
            }
        }
        return String(chars).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Emails

    static let mailProviders = ["gmail", "yahoo", "outlook", "hotmail", "icloud", "proton", "protonmail", "live", "aol", "me", "zoho"]

    /// "chandra at gmail.com" → "chandra@gmail.com". Only near "email/mail/address" or with a known
    /// mail provider, so "look at google.com" is left alone.
    static func emails(_ text: String) -> String {
        let regex = try! NSRegularExpression(pattern: #"\b([A-Za-z0-9._%+-]+) at ([A-Za-z0-9-]+)((?:\.[A-Za-z]{2,})+)\b"#)
        let ns = text as NSString
        var out = text
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let domain = ns.substring(with: m.range(at: 2)).lowercased()
            let before = ns.substring(to: m.range.location).lowercased().suffix(40)
            let emailContext = ["email", "e-mail", "mail", "address", "reach me", "contact"].contains { before.contains($0) }
            guard emailContext || mailProviders.contains(domain) else { continue }
            let address = (ns.substring(with: m.range(at: 1)) + "@" + domain + ns.substring(with: m.range(at: 3))).lowercased()
            out = (out as NSString).replacingCharacters(in: m.range, with: address)
        }
        return out
    }

    // MARK: - Bulleted lists

    static let listTriggers = [
        "list", "items", "things", "following", "need", "buy", "get", "grab", "bring", "pack", "groceries",
        "grocery", "shopping", "agenda", "to-do", "to do", "todo", "checklist", "tasks", "include", "includes",
    ]
    static let checklistTriggers = ["to-do", "to do", "todo", "checklist", "tasks"]

    /// Turns "intro a, b, c and d." into an intro line plus one item per line.
    static func bulletedList(_ line: String, style: OutputStyle) -> String? {
        // Work on the sentence that holds the enumeration; keep sentences around it.
        let sentences = splitSentences(line)
        for (index, sentence) in sentences.enumerated() {
            var introStart = index
            var list = parseEnumeration(sentence)
            if list == nil, let items = bareEnumeration(sentence) {
                // ASR often ends the sentence before the items: "…create a list. Avocado, egg, banana, milk."
                if index > 0, hasTrigger(sentences[index - 1]) {
                    let intro = sentences[index - 1].trimmingCharacters(in: CharacterSet(charactersIn: " .:"))
                    list = Enumeration(intro: intro, items: items)
                    introStart = index - 1
                } else if items.count >= 4 {
                    list = Enumeration(intro: "", items: items) // "Avocado, egg, banana, milk."
                }
            }
            guard let list else { continue }
            let marker = checklistTriggers.contains(where: list.intro.lowercased().contains) ? style.checkbox : style.bullet
            let body = list.items.map { marker + capitalizeFirst($0) }.joined(separator: "\n")
            let intro = list.intro.isEmpty ? "" : list.intro + ":\n"
            let before = sentences[..<introStart].joined(separator: " ")
            let after = sentences[(index + 1)...].joined(separator: " ")
            return [before, intro + body, after].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        return nil
    }

    /// A sentence that is nothing but short items: "Avocado, egg, banana, milk and water."
    static func bareEnumeration(_ sentence: String) -> [String]? {
        var s = sentence.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix("?") { return nil }
        if let last = s.last, ".!".contains(last) { s.removeLast() }
        var items = s.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if let lastItem = items.last, let r = lastItem.range(of: #"^(and|or) |\s(and|or)\s"#, options: .regularExpression) {
            let before = lastItem[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            let after = lastItem[r.upperBound...].trimmingCharacters(in: .whitespaces)
            items.removeLast()
            items += [before, after].filter { !$0.isEmpty }
        }
        guard items.count >= 3, items.allSatisfy({ !$0.isEmpty && wordCount($0) <= 3 }) else { return nil }
        return items
    }

    static func hasTrigger(_ text: String) -> Bool {
        let lower = " " + text.lowercased().filter { $0.isLetter || $0 == " " || $0 == "-" } + " "
        return listTriggers.contains { lower.contains(" \($0) ") }
    }

    struct Enumeration {
        var intro: String
        var items: [String]
    }

    static func parseEnumeration(_ sentence: String) -> Enumeration? {
        var s = sentence.trimmingCharacters(in: .whitespaces)
        if s.hasSuffix("?") { return nil } // "Can you bring the charger, the cable and the adapter?" stays a question
        if let last = s.last, ".!".contains(last) { s.removeLast() }
        var segments = s.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard segments.count >= 2 else { return nil }

        // "…, apple and banana" → split the last "and"/"or" into its own item.
        if let lastSeg = segments.last {
            let lower = lastSeg.lowercased()
            if lower.hasPrefix("and ") || lower.hasPrefix("or ") {
                segments[segments.count - 1] = String(lastSeg.drop { $0 != " " }.dropFirst())
            } else if let r = lastSeg.range(of: " and ", options: .backwards) ?? lastSeg.range(of: " or ", options: .backwards) {
                segments[segments.count - 1] = String(lastSeg[..<r.lowerBound])
                segments.append(String(lastSeg[r.upperBound...]))
            }
        }
        guard segments.count >= 3 else { return nil }

        // The first segment holds the intro plus the first item: "…buy tomorrow bread".
        var head = segments.removeFirst()
        var items = segments
        guard items.allSatisfy({ !$0.isEmpty && wordCount($0) <= 4 }) else { return nil }
        // Clauses, not items: "…, but not now, maybe later".
        let clauseStarts: Set<String> = ["but", "so", "because", "although", "though", "however", "maybe", "which",
                                         "who", "if", "when", "while", "yet", "then", "shall", "it's", "its", "i", "we"]
        guard !items.contains(where: { clauseStarts.contains(normalize(String($0.split(separator: " ").first ?? ""))) })
        else { return nil }

        var intro: String
        if let colon = head.firstIndex(of: ":") {
            intro = String(head[..<colon])
            head = String(head[head.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !head.isEmpty { items.insert(head, at: 0) }
        } else {
            var words = head.split(separator: " ").map(String.init)
            let split = firstItemStart(in: words, otherItems: items)
            guard split > 0 else { return nil } // no intro at all: "milk, eggs, bread"
            let first = words[split...].joined(separator: " ")
            words.removeSubrange(split...)
            intro = words.joined(separator: " ")
            items.insert(first, at: 0)
        }
        intro = intro.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        // Only format when the speaker is clearly listing ("I met John, Mary and Steve" stays prose).
        let lowerIntro = " " + intro.lowercased() + " "
        guard listTriggers.contains(where: { lowerIntro.contains(" \($0) ") || lowerIntro.contains(" \($0):") }) else {
            return nil
        }
        return Enumeration(intro: intro, items: items.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .")) })
    }

    static let timeWords: Set<String> = [
        "today", "tomorrow", "tonight", "morning", "evening", "afternoon", "week", "weekend", "month",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "later", "now",
    ]

    /// Where the first item begins inside "intro + first item" ("…buy tomorrow | bread").
    static func firstItemStart(in words: [String], otherItems: [String]) -> Int {
        let lengths = otherItems.map(wordCount).sorted()
        let typical = max(1, min(3, lengths[lengths.count / 2]))
        // 1. Right after a time word: "…for today | call the bank", "…buy tomorrow | bread".
        if let t = words.lastIndex(where: { timeWords.contains(normalize($0)) }), (1 ... 4).contains(words.count - t - 1) {
            return t + 1
        }
        // 2. Items that start with a verb ("pay rent", "book tickets"): the first item starts at the last verb.
        let firstWords = otherItems.compactMap { $0.split(separator: " ").first.map(String.init) }
        if firstWords.filter(isVerb).count * 2 > firstWords.count {
            for i in stride(from: words.count - 1, through: max(1, words.count - 4), by: -1) where isVerb(words[i]) {
                return i
            }
        }
        // 3. Same length as the other items.
        return words.count - typical
    }

    /// Cached, with one shared tagger: creating an NLTagger per word made long dictations take ~200 ms per pass.
    static func isVerb(_ word: String) -> Bool {
        let key = word.lowercased()
        return verbLock.withLock {
            if let known = verbCache[key] { return known }
            // Tag as an imperative so "book"/"call" read as verbs, not nouns.
            let text = key + " it"
            verbTagger.string = text
            let isVerb = verbTagger.tag(at: text.startIndex, unit: .word, scheme: .lexicalClass).0 == .verb
            if verbCache.count > 5_000 { verbCache.removeAll() }
            verbCache[key] = isVerb
            return isVerb
        }
    }

    private static let verbLock = NSLock()
    nonisolated(unsafe) private static var verbCache: [String: Bool] = [:]
    nonisolated(unsafe) private static let verbTagger = NLTagger(tagSchemes: [.lexicalClass])

    // MARK: - Numbered lists

    static let ordinals = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]
    static let cardinals = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]

    /// "To deploy, first run the tests, second build the app, third push." → "To deploy:\n1. Run the tests…"
    static func numberedList(_ line: String, style: OutputStyle) -> String? {
        let words = line.split(separator: " ").map(String.init)
        var markers: [(index: Int, length: Int)] = []
        var expected = 1
        var i = 0
        while i < words.count {
            // Items are short: a marker far from the last one belongs to something else.
            if let last = markers.last, i - last.index > 25 { break }
            let w = normalize(words[i])
            let next = i + 1 < words.count ? normalize(words[i + 1]) : ""
            let n = expected - 1
            let prev = i > 0 ? normalize(words[i - 1]) : ""
            // "the first draft", "my second job": an ordinary word, not a list marker.
            let determiners: Set<String> = ["the", "a", "an", "my", "our", "your", "his", "her", "their", "its", "this",
                                            "that", "every", "each"]
            if n < ordinals.count, w == ordinals[n] || w == ordinals[n] + "ly", !determiners.contains(prev) {
                markers.append((i, 1)); expected += 1
            } else if n < cardinals.count, ["step", "number", "point"].contains(w),
                      next == cardinals[n] || next == String(expected)
            {
                markers.append((i, 2)); expected += 1; i += 1
            } else if markers.count >= 2, ["finally", "lastly"].contains(w) {
                markers.append((i, 1)); expected += 1
                break
            }
            i += 1
        }
        guard markers.count >= 3 || (markers.count == 2 && markers[0].length == 2) else { return nil }

        let intro = words[..<markers[0].index].joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,:"))
        // The last item ends with its sentence; whatever follows is ordinary text after the list.
        var lastEnd = words.count
        if let last = markers.last {
            for j in (last.index + last.length) ..< words.count where ".!?".contains(words[j].last ?? " ") {
                lastEnd = j + 1
                break
            }
        }
        let rest = words[lastEnd...].joined(separator: " ")
        // Items are short; a "first … second …" spread across paragraphs is prose, not a list.
        for (k, m) in markers.enumerated() {
            let end = k + 1 < markers.count ? markers[k + 1].index : lastEnd
            if end - (m.index + m.length) > 20 { return nil }
        }
        var items: [String] = []
        for (k, m) in markers.enumerated() {
            let end = k + 1 < markers.count ? markers[k + 1].index : lastEnd
            var item = words[(m.index + m.length) ..< end].joined(separator: " ")
            item = item.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:"))
            if item.lowercased().hasSuffix(" and") { item = String(item.dropLast(4)) }
            if k + 1 < markers.count { item = item.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            items.append(capitalizeFirst(item.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))))
        }
        let body = items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let head = intro.isEmpty ? "" : capitalizeFirst(intro) + (".!?".contains(intro.last ?? " ") ? "\n" : ":\n")
        return head + body + (rest.isEmpty ? "" : "\n\n" + rest)
    }

    // MARK: - Helpers

    static func splitSentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            current.append(c)
            if ".?!".contains(c), i + 1 == chars.count || chars[i + 1] == " " {
                out.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { out.append(current.trimmingCharacters(in: .whitespaces)) }
        return out
    }

    static func wordCount(_ s: String) -> Int { s.split(separator: " ").count }

    static func normalize(_ w: String) -> String {
        w.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func capitalizeFirst(_ s: String) -> String {
        guard let f = s.first, f.isLowercase else { return s }
        return f.uppercased() + s.dropFirst()
    }
}
