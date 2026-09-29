import Foundation

/// A recorded class: what was said (with times), which slide it was on, and the notes Evoo wrote.
public struct ClassSession: Codable, Identifiable, Equatable, Sendable {
    public struct Segment: Codable, Equatable, Sendable {
        /// Seconds since the class started.
        public var time: TimeInterval
        /// Slide / page (0-based) the professor was on, if a PDF was added.
        public var page: Int?
        public var text: String

        public init(time: TimeInterval, page: Int?, text: String) {
            self.time = time
            self.page = page
            self.text = text
        }
    }

    public struct Note: Codable, Equatable, Sendable {
        public var time: TimeInterval
        public var page: Int?
        public var text: String

        public init(time: TimeInterval, page: Int?, text: String) {
            self.time = time
            self.page = page
            self.text = text
        }
    }

    public var id = UUID()
    public var title: String
    public var started: Date
    /// File name of the class material inside the session folder, if one was added.
    public var pdfFile: String?
    public var segments: [Segment] = []
    public var notes: [Note] = []

    public init(title: String, started: Date = Date(), pdfFile: String? = nil) {
        self.title = title
        self.started = started
        self.pdfFile = pdfFile
    }

    /// Notes as Markdown, grouped by slide when there is one.
    public func markdown() -> String {
        var out = "# \(title)\n\n_\(started.formatted(date: .complete, time: .shortened))_\n"
        var lastPage: Int?? = .none
        for note in notes {
            if lastPage == .none || lastPage! != note.page {
                out += "\n## " + (note.page.map { "Slide \($0 + 1)" } ?? "Notes") + "\n\n"
                lastPage = .some(note.page)
            }
            out += note.text + "\n"
        }
        return out
    }
}

/// Follows which slide the professor is on by matching recent speech against each slide's text.
/// Moves forward readily, back only on clear evidence, and never jumps far on a weak match.
public struct SlideTracker: Sendable {
    public let pages: [String]
    public private(set) var current = 0

    public init(pages: [String]) {
        self.pages = pages
    }

    /// Call with the last minute or so of transcript. Returns the (possibly new) current page.
    @discardableResult
    public mutating func update(with recent: String) -> Int {
        guard pages.count > 1, !recent.isEmpty else { return current }
        let lower = recent.lowercased()
        // Spoken navigation: "next slide", "slide 12", "page 5".
        if let n = lower.range(of: #"(?:slide|page) (?:number )?(\d{1,3})\b"#, options: .regularExpression)
            .flatMap({ Int(lower[$0].filter(\.isNumber)) }), n >= 1, n <= pages.count
        {
            current = n - 1
            return current
        }
        let scores = SemanticSearch.scores(recent, in: pages)
        let window = max(0, current - 1) ... min(pages.count - 1, current + 3)
        guard let best = window.max(by: { scores[$0] < scores[$1] }) else { return current }
        let margin = best > current ? 0.08 : 0.2 // going back needs stronger evidence
        if best != current, scores[best] > scores[current] + margin { current = best }
        return current
    }

    public mutating func set(_ page: Int) {
        current = min(max(0, page), max(0, pages.count - 1))
    }
}

/// Notes without an AI model: lecture speech → short, clean bullets; emphasised points get a ★.
public enum LectureNotes {
    static let emphasis = ["important", "remember", "exam", "key point", "definition", "defined as", "formula",
                           "note that", "make sure", "don't forget", "the main", "in summary", "always", "never",
                           "theorem", "rule", "trick", "common mistake"]
    static let openers = #"^(?i)(?:so|okay|ok|alright|right|now|well|and|um|uh|you know|basically)[,]?\s+"#

    /// Turns a stretch of lecture transcript into note bullets.
    public static func bullets(from transcript: String) -> [String] {
        let cleaned = DictationRules.apply(transcript).text
        return sentences(cleaned).compactMap { sentence in
            var s = sentence
            while let r = s.range(of: openers, options: .regularExpression) { s.removeSubrange(r) }
            s = s.trimmingCharacters(in: .whitespaces)
            guard s.split(separator: " ").count >= 5 else { return nil } // skip "Right?" / "Any questions?"
            if s.hasSuffix("?"), !emphasis.contains(where: s.lowercased().contains) { return nil }
            let star = emphasis.contains(where: s.lowercased().contains) || s.contains(where: \.isNumber)
            return (star ? "- ★ " : "- ") + (s.prefix(1).uppercased() + s.dropFirst())
        }
    }

    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { s, _, _, _ in
            if let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { out.append(s) }
        }
        return out
    }
}

/// Prompt for the local LLM (16 GB Macs) to write notes like a student would.
public enum ClassNotePrompt {
    static let system = """
    You take lecture notes for a student. You get the current slide (if any) and what the professor just \
    said. Write concise notes of what the professor ADDED — explanations, intuition, worked examples with the \
    numbers, what they stressed, questions from students. Don't copy the slide. Use short "- " bullets, "→" for \
    implications, "★" for anything stressed as important or on the exam, and LaTeX for math between $…$ \
    (e.g. $P(A\\mid B)=\\frac{P(B\\mid A)P(A)}{P(B)}$). If nothing new was said, output nothing.
    """

    public static var prefix: String { "<|im_start|>system\n\(system)<|im_end|>\n" }

    public static func suffix(slide: String?, transcript: String, thinkBlock: Bool) -> String {
        let slidePart = slide.map { "Slide:\n\(String($0.prefix(1_500)))\n\n" } ?? ""
        return "<|im_start|>user\n\(slidePart)Professor said:\n\(transcript)<|im_end|>\n<|im_start|>assistant\n"
            + (thinkBlock ? "<think>\n\n</think>\n\n" : "")
    }
}

/// Finds where something was said or noted across all classes.
public enum ClassSearch {
    public struct Hit: Identifiable, Equatable, Sendable {
        public var id: String { "\(sessionID)-\(time)" }
        public var sessionID: UUID
        public var time: TimeInterval
        public var page: Int?
        public var snippet: String
    }

    public static func search(_ query: String, in sessions: [ClassSession], limit: Int = 50) -> [Hit] {
        var candidates: [Hit] = []
        for s in sessions {
            candidates += s.notes.map { Hit(sessionID: s.id, time: $0.time, page: $0.page, snippet: $0.text) }
            candidates += s.segments.map { Hit(sessionID: s.id, time: $0.time, page: $0.page, snippet: $0.text) }
        }
        return SemanticSearch.rank(query, in: candidates.map(\.snippet), limit: limit).map { candidates[$0] }
    }
}
