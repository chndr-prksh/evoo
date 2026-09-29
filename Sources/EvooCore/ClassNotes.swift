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
        /// Typed by the student during class (vs. written by Evoo).
        public var mine: Bool?

        public init(time: TimeInterval, page: Int?, text: String, mine: Bool? = nil) {
            self.time = time
            self.page = page
            self.text = text
            self.mine = mine
        }
    }

    /// A moment the student flagged during class.
    public struct Mark: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, CaseIterable, Sendable {
            case important, confusing, exam

            public var label: String {
                switch self {
                case .important: "Important"
                case .confusing: "Confusing"
                case .exam: "On the exam"
                }
            }

            public var symbol: String {
                switch self {
                case .important: "★"
                case .confusing: "❓"
                case .exam: "🎯"
                }
            }
        }

        public var time: TimeInterval
        public var kind: Kind

        public init(time: TimeInterval, kind: Kind) {
            self.time = time
            self.kind = kind
        }
    }

    /// Made after class from the notes: for review and active recall.
    public struct StudyPack: Codable, Equatable, Sendable {
        public struct Card: Codable, Equatable, Sendable {
            public var front: String
            public var back: String
        }

        public struct Term: Codable, Equatable, Sendable {
            public var term: String
            public var meaning: String
        }

        public var summary: String = ""
        public var terms: [Term] = []
        public var questions: [String] = []
        public var flashcards: [Card] = []
        public var todos: [String] = []
        /// "Label: $$formula$$" lines (packs made before this existed have none).
        public var formulas: [String]? = nil
    }

    public var id = UUID()
    public var title: String
    /// What the class is about ("Probability", "Constitutional Law") — sets how notes are written.
    public var subject: String?
    public var started: Date
    /// File name of the class material inside the session folder, if one was added.
    public var pdfFile: String?
    public var segments: [Segment] = []
    public var notes: [Note] = []
    public var marks: [Mark]? = []
    /// Recording of the lecture (older classes only — Evoo no longer records audio).
    public var audioFile: String?
    /// The notes as one Markdown document the student can edit; the AI appends to it as the lecture goes.
    /// Classes from before this existed are built from `notes`.
    public var document: String?
    public var studyPack: StudyPack?
    public var duration: TimeInterval?

    public init(title: String, subject: String? = nil, started: Date = Date(), pdfFile: String? = nil) {
        self.title = title
        self.subject = subject
        self.started = started
        self.pdfFile = pdfFile
    }

    /// The notes document (the edited one, or the AI's notes joined for older classes).
    public var notesText: String {
        document ?? notes.map { $0.mine == true ? "> ✍️ " + $0.text : $0.text }.joined(separator: "\n\n")
    }

    /// Notes as Markdown (the notes carry their own topic headings).
    public func markdown() -> String {
        var out = "# \(title)\n\n_\(subject.map { $0 + " · " } ?? "")\(started.formatted(date: .complete, time: .shortened))_\n\n"
        if let pack = studyPack, !pack.summary.isEmpty { out += "## Summary\n\n\(pack.summary)\n\n" }
        if let formulas = studyPack?.formulas, !formulas.isEmpty {
            out += "## Key formulas\n\n" + formulas.map { "- " + $0 }.joined(separator: "\n") + "\n\n"
        }
        out += notesText + "\n"
        if let pack = studyPack {
            if !pack.terms.isEmpty {
                out += "\n## Key terms\n\n" + pack.terms.map { "- **\($0.term)** — \($0.meaning)" }.joined(separator: "\n") + "\n"
            }
            if !pack.questions.isEmpty {
                out += "\n## Practice questions\n\n" + pack.questions.map { "- \($0)" }.joined(separator: "\n") + "\n"
            }
            if !pack.flashcards.isEmpty {
                out += "\n## Flashcards\n\n" + pack.flashcards.map { "- **Q:** \($0.front)  \n  **A:** \($0.back)" }
                    .joined(separator: "\n") + "\n"
            }
            if !pack.todos.isEmpty {
                out += "\n## To do\n\n" + pack.todos.map { "- [ ] \($0)" }.joined(separator: "\n") + "\n"
            }
        }
        return out
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

/// Prompt for the local LLM to write structured notes the way a strong student in that subject would.
public enum ClassNotePrompt {
    /// Written the way a good student takes notes by hand: listen, decide what matters, write the point in as few
    /// words as possible. Most of what's said is never written down.
    static let system = """
    You are a sharp student taking notes by hand in a lecture. You hear about a minute at a time. Like a real \
    note-taker, you don't transcribe — you decide what matters and jot it down in as few words as possible.
    Write down:
    - definitions and new terms; formulas; lists, steps, types, rules
    - the key numbers, dates, names that matter
    - cause → effect, comparisons (X vs Y), the one-line point of an example or story
    - anything the professor stresses, repeats, writes on the board, or says is on the exam (mark ★)
    - homework, readings, deadlines, exam dates
    Skip: greetings, introductions, jokes, anecdote details, repetition, "as I said", rhetorical questions, \
    tangents, filler. If nothing new and important was said, write nothing at all.
    How it looks:
    - Usually 1–4 lines for a minute of lecture. Lines start with "- ". Indent a sub-point with "  - ".
    - Fragments, not sentences: drop "the", "a", "is"; abbreviate (w/, b/c, e.g., ≈, def, ex); symbols =, ≠, →, vs.
    - "## Topic" only when a new topic begins — never repeat the current topic.
    - **bold** a new term the first time: "**term** — meaning".
    - Formulas in LaTeX: $…$ inline, $$…$$ for a key formula. Code in `backticks`.
    - Fit the subject: math/science → formulas, derivation steps; history/politics → date — event, cause → \
    effect; law → rule, case, test; biology/medicine → process steps; business/economics → concept + example; \
    literature → quote, theme.
    - Only what was said. Never explain, interpret, or comment on the lecture or the transcript.
    Example — Subject: Probability. Heard: "okay so, um, good morning, hope the weekend was good. Today, \
    conditional probability. Probability of A given B, we write P of A given B, equals P of A and B over P of B. \
    Really important, it'll be on the midterm. So like, you roll a die and I tell you it's even, what's the chance \
    it's a six? One in three. Right, one in three, because only three outcomes are left."
    Notes:
    ## Conditional probability
    - $$P(A\\mid B)=\\frac{P(A\\cap B)}{P(B)}$$ ★ midterm
    - ex: die even → P(6) = 1/3 (3 outcomes left)
    """

    public static var prefix: String { "<|im_start|>system\n\(system)<|im_end|>\n" }

    public static func suffix(subject: String?, lastTopic: String?, recent: String = "", transcript: String,
                              marks: [ClassSession.Mark.Kind] = [], thinkBlock: Bool) -> String
    {
        var user = "Subject: \(subject?.isEmpty == false ? subject! : "General")\n"
        if let lastTopic { user += "Current topic: \(lastTopic)\n" }
        let recent = recent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !recent.isEmpty {
            user += "The end of your notes so far (continue from here; don't repeat anything already written):\n\(recent)\n"
        }
        for kind in Set(marks) {
            switch kind {
            case .important: user += "The student flagged this part as IMPORTANT — mark its key point with ★.\n"
            case .exam: user += "The student flagged this part as ON THE EXAM — mark it with ★ and \"(exam)\".\n"
            case .confusing: user += "The student found this part CONFUSING — add a bullet starting \"❓ In plain words:\" that explains it simply.\n"
            }
        }
        user += "\nHeard:\n\(transcript)"
        return "<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n" + (thinkBlock ? "<think>\n\n</think>\n\n" : "")
    }

    /// Cleans the model's notes: drops a repeated heading for the current topic, commentary about the lecture,
    /// and ★ lines that only editorialize; keeps it to a handful of bullets.
    /// Also drops lines already in the notes (`existing`), and ★ that the lecture never earned: a star stays only
    /// if the professor said something like "important" / "exam" in `heard`, or the student flagged the moment.
    public static func tidy(_ notes: String, lastTopic: String?, existing: String = "", heard: String? = nil,
                            flagged: Bool = false) -> String
    {
        var text = tidy(notes, lastTopic: lastTopic)
        let stressed = flagged || heard.map { $0.range(of: stressCue, options: [.regularExpression, .caseInsensitive]) != nil } ?? true
        if !stressed {
            text = text.replacingOccurrences(of: #"\s*\(?★[^\n)]*\)?"#, with: "", options: .regularExpression)
        }
        let seen = Set(existing.split(separator: "\n").map { key(String($0)) }.filter { $0.count >= 8 })
        let seenWords = existing.split(separator: "\n").map { words(String($0)) }.filter { $0.count >= 3 }
        var out: [String] = []
        var keptBullet = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("-") {
                let k = key(t), w = words(t)
                let repeated = seen.contains(k) || (w.count >= 3 && seenWords.contains { overlap(w, $0) >= 0.75 })
                if repeated || t.range(of: #"(?i)\b(?:likely|probably|presumably|perhaps|possibly)\b|\(note:"#,
                                         options: .regularExpression) != nil { continue }
                keptBullet = true
            }
            out.append(line)
        }
        // A heading with nothing under it is just noise.
        if !keptBullet { return "" }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let stressCue = #"\b(?:important|exam|final|midterm|quiz|test|remember|write (?:this|that) down|key (?:point|idea|thing)|crucial|must know|make sure|don'?t forget|pay attention|will come up|going to (?:ask|come up))\b"#

    static func key(_ line: String) -> String {
        let body = line.components(separatedBy: "★").first ?? line
        return body.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func words(_ line: String) -> Set<String> {
        Set(line.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init).filter { $0.count > 2 })
    }

    static func overlap(_ a: Set<String>, _ b: Set<String>) -> Double {
        Double(a.intersection(b).count) / Double(max(1, min(a.count, b.count)))
    }

    static func tidy(_ notes: String, lastTopic: String?) -> String {
        let commentary = #"(?i)^(?:[-*•★]\s*)*(?:key point|this (?:illustrates|shows|reflects|highlights|case|event|segment)|the (?:speaker|professor|lecturer) (?:describes|emphasi[sz]es|notes|introduces|plans|discusses|explains|highlights|mentions|says)|no substantive|note:|\(likely|likely a typo|in summary|overall,)"#
        var out: [String] = []
        var bullets = 0
        for raw in notes.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw).replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let title = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                if let lastTopic, same(title, lastTopic) { continue }
                out.append("## " + title)
                continue
            }
            if trimmed.range(of: commentary, options: .regularExpression) != nil { continue }
            if trimmed.lowercased().hasPrefix("example:") && trimmed.count < 10 { continue } // empty "Example:" label
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                if !line.hasPrefix(" ") { bullets += 1 }
                if bullets > 8 { continue }
                line = line.replacingOccurrences(of: #"^(\s*)[*•] "#, with: "$1- ", options: .regularExpression)
            }
            out.append(line)
        }
        // Collapse blank runs and trim.
        return out.joined(separator: "\n").replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func same(_ a: String, _ b: String) -> Bool {
        let norm = { (s: String) in s.lowercased().filter { $0.isLetter || $0 == " " }.split(separator: " ").joined(separator: " ") }
        let x = norm(a), y = norm(b)
        return x == y || x.hasPrefix(y) || y.hasPrefix(x)
    }

    /// The last "## Topic" heading in the notes so far.
    public static func lastTopic(in notes: [String]) -> String? {
        for note in notes.reversed() {
            if let line = note.split(separator: "\n").last(where: { $0.hasPrefix("## ") }) {
                return String(line.dropFirst(3))
            }
        }
        return nil
    }

    /// Subjects offered when starting a class (anything else can be typed).
    public static let commonSubjects = [
        "Mathematics", "Probability & Statistics", "Physics", "Chemistry", "Biology", "Computer Science",
        "Economics", "Business", "History", "Political Science", "Law", "Medicine", "Psychology",
        "Literature", "Philosophy", "Engineering",
    ]
}

/// After class: summary, key terms, practice questions, flashcards and to-dos from the notes.
public enum StudyPackPrompt {
    static let system = """
    You turn a student's lecture notes into a short study sheet. Use only what's in the notes. Be brief — \
    fragments, not paragraphs. Output exactly these sections, in this order, with these headings:
    ## Summary
    - 3 bullets, each at most 20 words: the lecture's main ideas.
    ## Key formulas
    - Short label: $$formula$$   (every important formula, in LaTeX; write "- None" if there are none)
    ## Key terms
    - **Term** — meaning in at most 12 words   (at most 6 terms)
    ## Practice questions
    - An exam-style question   (3–5 of them)
    ## Flashcards
    - Q: short question | A: answer in at most 10 words   (6–10 of them; formulas in $…$)
    ## To do
    - Assignments, readings, deadlines or exam dates mentioned (write "- None" if there are none).
    """

    public static var prefix: String { "<|im_start|>system\n\(system)<|im_end|>\n" }

    public static func suffix(subject: String?, notes: String, thinkBlock: Bool) -> String {
        "<|im_start|>user\nSubject: \(subject ?? "General")\n\nNotes:\n\(notes)<|im_end|>\n<|im_start|>assistant\n"
            + (thinkBlock ? "<think>\n\n</think>\n\n" : "")
    }

    /// Reads the model's sections back into a study pack (tolerant of small format slips).
    public static func parse(_ text: String) -> ClassSession.StudyPack {
        var pack = ClassSession.StudyPack()
        var section = ""
        var summary: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                section = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                continue
            }
            guard !line.isEmpty else { continue }
            let item = line.replacingOccurrences(of: #"^(?:[-*•]|\d+[.)])\s*"#, with: "", options: .regularExpression)
            switch true {
            case section.hasPrefix("summary"): summary.append(item)
            case section.hasPrefix("key formula"), section.hasPrefix("formula"):
                if item.lowercased() != "none" { pack.formulas = (pack.formulas ?? []) + [item] }
            case section.hasPrefix("key term"):
                let parts = item.components(separatedBy: " — ").count > 1 ? item.components(separatedBy: " — ")
                    : item.components(separatedBy: " - ")
                if parts.count >= 2 {
                    pack.terms.append(.init(term: parts[0].replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces),
                                            meaning: parts.dropFirst().joined(separator: " — ").trimmingCharacters(in: .whitespaces)))
                }
            case section.hasPrefix("practice"), section.hasPrefix("question"): pack.questions.append(item)
            case section.hasPrefix("flashcard"):
                let parts = item.components(separatedBy: "|")
                if parts.count >= 2 {
                    let clean = { (s: String) in s.trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: #"^[QA]:\s*"#, with: "", options: .regularExpression) }
                    pack.flashcards.append(.init(front: clean(parts[0]), back: clean(parts.dropFirst().joined(separator: "|"))))
                }
            case section.hasPrefix("to do"), section.hasPrefix("todo"):
                if item.lowercased() != "none" { pack.todos.append(item) }
            default: break
            }
        }
        pack.summary = summary.map { "- " + $0 }.joined(separator: "\n")
        return pack
    }
}

/// "Ask your lecture": answers from what was said, pointing to when.
public enum LectureQAPrompt {
    static let system = """
    You answer a student's question about a lecture, using only the transcript excerpts given (each starts with \
    its time, like [12:40]). Answer clearly in a few sentences, with formulas in LaTeX between $…$, and cite the \
    times you used like (12:40). If the lecture didn't cover it, say so.
    """

    public static var prefix: String { "<|im_start|>system\n\(system)<|im_end|>\n" }

    public static func suffix(question: String, excerpts: String, thinkBlock: Bool) -> String {
        "<|im_start|>user\nTranscript excerpts:\n\(excerpts)\n\nQuestion: \(question)<|im_end|>\n<|im_start|>assistant\n"
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
