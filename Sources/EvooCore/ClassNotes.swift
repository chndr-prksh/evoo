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
    /// Recording of the lecture (file name in the class folder), for replaying any moment.
    public var audioFile: String?
    public var studyPack: StudyPack?
    public var duration: TimeInterval?

    public init(title: String, subject: String? = nil, started: Date = Date(), pdfFile: String? = nil) {
        self.title = title
        self.subject = subject
        self.started = started
        self.pdfFile = pdfFile
    }

    /// Notes as Markdown (the notes carry their own topic headings).
    public func markdown() -> String {
        var out = "# \(title)\n\n_\(subject.map { $0 + " · " } ?? "")\(started.formatted(date: .complete, time: .shortened))_\n\n"
        if let pack = studyPack, !pack.summary.isEmpty { out += "## Summary\n\n\(pack.summary)\n\n" }
        out += notes.map { $0.mine == true ? "> ✍️ " + $0.text : $0.text }.joined(separator: "\n\n") + "\n"
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
    static let system = """
    You take structured lecture notes for a student. You get the subject, the topic you were last writing \
    about, and what the professor just said. Write clear, well-organized notes of it:
    - Start a new topic with a heading line "## Topic name" — only when the professor moves to a new topic; \
    otherwise continue the current one without a heading.
    - Use short "- " bullets, indented "  - " for details. Put key terms in **bold**; write a definition as \
    "**Term** — meaning".
    - Keep worked examples with their actual numbers or specifics, labelled "Example:".
    - Mark anything the professor stresses as important, or says is on the exam, with "★".
    - Write it the way notes in this subject are normally written: math, statistics, physics, engineering → \
    formulas in LaTeX between $…$ ($$…$$ for important ones), steps of derivations; programming → code in \
    backticks, complexity; history, politics → dates, people, cause → effect; law → rules, cases, tests; \
    biology, chemistry, medicine → mechanisms, processes as steps, terminology; economics, business → \
    models, definitions, graphs described in words; languages, literature → quotes, themes, examples.
    - Only what was actually said — never invent facts. Skip filler, jokes and logistics unless they matter \
    (like exam dates). If nothing substantive was said, output nothing.
    """

    public static var prefix: String { "<|im_start|>system\n\(system)<|im_end|>\n" }

    public static func suffix(subject: String?, lastTopic: String?, transcript: String, marks: [ClassSession.Mark.Kind] = [],
                              thinkBlock: Bool) -> String
    {
        var user = "Subject: \(subject?.isEmpty == false ? subject! : "General")\n"
        if let lastTopic { user += "Current topic: \(lastTopic)\n" }
        for kind in Set(marks) {
            switch kind {
            case .important: user += "The student flagged this part as IMPORTANT — mark its key point with ★.\n"
            case .exam: user += "The student flagged this part as ON THE EXAM — mark it with ★ and \"(exam)\".\n"
            case .confusing: user += "The student found this part CONFUSING — add a bullet starting \"❓ In plain words:\" that explains it simply.\n"
            }
        }
        user += "\nProfessor said:\n\(transcript)"
        return "<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n" + (thinkBlock ? "<think>\n\n</think>\n\n" : "")
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
    You turn a student's lecture notes into a study pack. Use only what's in the notes. Output exactly these \
    sections, in this order, with these headings:
    ## Summary
    3–5 sentences covering the lecture's main ideas.
    ## Key terms
    - **Term** — one-line meaning
    ## Practice questions
    - A question a professor could ask on an exam (5–8 of them).
    ## Flashcards
    - Q: question | A: short answer   (8–15 of them)
    ## To do
    - Assignments, readings, deadlines or exam dates mentioned (write "- None" if there are none).
    Keep formulas in LaTeX between $…$.
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
            case section.hasPrefix("summary"): summary.append(line)
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
        pack.summary = summary.joined(separator: " ")
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
