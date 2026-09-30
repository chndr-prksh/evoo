import Foundation

/// Corrections for Hinglish dictation — used only when the language is Hinglish, so English is unaffected.
///
/// Hinglish restarts repeat the end of the phrase with a new beginning, often without the cue word surviving
/// transcription (the Hinglish model tends to drop "nahi" / "sorry"):
///   "Kal milte, nahi, parson milte hain"        → "Parson milte hain"
///   "Rahul ko message, sorry, Amit ko message bhejo" → "Amit ko message bhejo"
///   "Mujhe do nahi, teen tickets chahiye"        → "Mujhe teen tickets chahiye"
public enum HinglishRules {
    static let cues = ["mera matlab", "matlab", "nahi", "nahin", "sorry", "i mean", "actually"]
    static let hindiNumbers: Set<String> = ["ek", "do", "teen", "char", "chaar", "paanch", "panch", "chhe", "che", "saat",
                                            "aath", "nau", "das", "bees", "pachaas", "sau"]
    /// Words that join two separate thoughts: a repeat across them isn't a correction.
    static let joiners: Set<String> = ["aur", "lekin", "par", "ya", "and", "but", "or", "phir", "fir", "kyunki", "toh", "to"]
    static let function: Set<String> = ["ko", "ki", "ka", "ke", "hai", "hain", "se", "me", "mein", "ne", "bhi", "to", "toh",
                                        "the", "a", "is", "ho", "tha", "thi"]

    public static func apply(_ text: String) -> String {
        var out = text
        // "do nahi, teen" → "teen": a number taken back and replaced.
        let numbers = hindiNumbers.joined(separator: "|")
        out = out.replacingOccurrences(of: "(?i)\\b(?:\(numbers)|\\d+),?\\s+(?:nahi|nahin|no),?\\s+((?:\(numbers)|\\d+))\\b",
                                       with: "$1", options: .regularExpression)
        // A cue word standing on its own between commas marks a correction; drop it (the restart rule does the rest).
        for cue in cues {
            out = out.replacingOccurrences(of: "(?i),?\\s*\\b\(cue)\\b\\s*,", with: " ", options: .regularExpression)
        }
        out = out.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return out.split(separator: "\n", omittingEmptySubsequences: false)
            .map { sentences(String($0)).map(restart).joined(separator: " ") }
            .joined(separator: "\n")
    }

    static func sentences(_ line: String) -> [String] {
        var out: [String] = [], cur = ""
        for c in line {
            cur.append(c)
            if ".?!".contains(c) { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
        }
        let rest = cur.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { out.append(rest) }
        return out
    }

    /// "Kal milte parson milte hain": the same words ("milte") come back after 1–3 new words ("parson"), so those
    /// replace the same number of words before the first occurrence ("Kal").
    static func restart(_ sentence: String) -> String {
        var words = sentence.split(separator: " ").map(String.init)
        func norm(_ w: String) -> String { w.lowercased().filter { $0.isLetter || $0.isNumber } }
        var changed = true
        while changed {
            changed = false
            let n = words.map(norm)
            search: for len in stride(from: 3, through: 1, by: -1) {
                guard n.count >= 2 * len + 1 else { continue }
                for i in 0 ... (n.count - 2 * len - 1) {
                    let gram = Array(n[i ..< i + len])
                    // One-word repeats must be a real word ("milte"), not "ko"/"hai".
                    if len == 1, gram[0].count < 4 || function.contains(gram[0]) { continue }
                    if gram.allSatisfy(function.contains) { continue }
                    for k in 1 ... 3 {
                        let j = i + len + k
                        guard j + len <= n.count, Array(n[j ..< j + len]) == gram, i - k >= 0 else { continue }
                        let between = n[(i + len) ..< j]
                        let replaced = n[(i - k) ..< i]
                        guard !between.contains(where: joiners.contains), !replaced.contains(where: joiners.contains),
                              Array(replaced) != Array(between),
                              !words[(i + len - 1) ..< j].contains(where: { ".?!".contains($0.last ?? " ") })
                        else { continue }
                        words.removeSubrange((i - k) ..< (i + len))
                        changed = true
                        break search
                    }
                }
            }
        }
        var s = words.joined(separator: " ")
        if let f = s.first, f.isLowercase { s = f.uppercased() + s.dropFirst() }
        return s
    }
}
