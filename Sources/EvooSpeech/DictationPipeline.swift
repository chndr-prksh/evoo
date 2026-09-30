import EvooCore
import EvooRefine
import FluidAudio
import Foundation

/// Audio → final text, with per-stage timings. Shared by the app and `evoo-cli`.
///
///   ASR ─▶ TextCleaner ─▶ personal dictionary ─▶ DictationRules ─▶ DictationFormatter ─▶ numbers (NeMo ITN)
///       ─▶ LLM (only if needed)
///
/// The first four stages are fast (ASR ≈ 100–300 ms, the rest < 5 ms). The LLM costs ~1 s on an 8 GB M1,
/// so it only runs when the rules flag an unresolved correction, or for Hinglish/Hindi.
public final class DictationPipeline {
    public struct Output: Sendable {
        public var text: String
        public var raw: String
        public var asrMs: Int
        public var postMs: Int
        public var refineMs: Int
        public var usedLLM: Bool
        /// A spoken command to carry out: press Return after pasting, or undo the last dictation.
        public var action: DictationCommands.Action? = nil
        /// Names from the screen that corrected this dictation ("Deva" → "Divya") — worth learning for good.
        public var usedScreenTerms: [String] = []

        public var totalMs: Int { asrMs + postMs + refineMs }

        public var summary: String {
            "ASR \(asrMs) ms · rules \(postMs) ms" + (usedLLM ? " · LLM \(refineMs) ms" : "") + " · total \(totalMs) ms"
        }
    }

    public enum LLMPolicy: Sendable {
        /// Never run the LLM (fastest).
        case off
        /// Only for unresolved corrections and non-English output.
        case whenNeeded
        /// Deletion-only self-correction by a small LLM, only when a correction word is present.
        case corrections
        /// Smart cleanup (16 GB+ Macs): the local LLM polishes every non-trivial dictation after the rules.
        case polish
    }

    private let refiner: LlamaRefiner
    private let normalizer = TextNormalizer.shared
    /// Names and terms to spell right ("Divya"). Set from the user's settings.
    public var dictionary = PersonalDictionary([])
    /// Voice shortcuts ("my email" → address). Set from the user's settings.
    public var snippets: [Snippet] = []

    /// macOS's built-in English word list, used so real words are never "corrected" into names.
    private static let knownWords: Set<String> = {
        guard let text = try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").map { $0.lowercased() })
    }()

    public static func isKnownWord(_ word: String) -> Bool { knownWords.contains(word) }

    /// Loads the word list off the critical path (takes ~100 ms once).
    public static func preload() {
        DispatchQueue.global(qos: .utility).async {
            _ = knownWords.count
            _ = DictationRules.apply("Email him, no, call him.") // loads Apple's language tagger (~300 ms once)
        }
    }

    public init(refiner: LlamaRefiner) {
        self.refiner = refiner
    }

    public func run(samples: [Float], engine: SpeechEngine, language: DictationLanguage,
                    style: OutputStyle? = .plain, llm: LLMPolicy) async throws -> Output
    {
        let clock = ContinuousClock()
        let t = clock.now
        let raw = try await Self.transcribe(samples, engine: engine, language: language)
        return await finish(raw: raw, asrMs: (clock.now - t).ms, language: language, style: style, llm: llm)
    }

    /// Speech → raw text, skipping the silence before and after the speech.
    public static func transcribe(_ samples: [Float], engine: SpeechEngine, language: DictationLanguage)
        async throws -> String
    {
        guard let speech = AudioStats.speechRange(samples) else { return "" }
        return try await engine.transcribe(Array(samples[speech]), language: language)
    }

    /// Raw text → final text (rules, formatting, numbers, optional LLM).
    /// `contextTerms`: names seen on screen for this dictation only (see `ContextVocabulary`).
    public func finish(raw: String, asrMs: Int, language: DictationLanguage, style: OutputStyle?,
                       contextTerms: [String] = [], tone: Tone = .neutral, llm: LLMPolicy,
                       polisher: StreamingPolisher? = nil) async -> Output
    {
        let clock = ContinuousClock()
        var t = clock.now
        let post = postProcess(raw, language: language, style: style, contextTerms: contextTerms)
        let postTime = clock.now - t

        var text = post.text
        var refineTime: Duration = .zero
        var usedLLM = false
        switch post.action {
        case .undo, .edit:
            return Output(text: "", raw: raw, asrMs: asrMs, postMs: postTime.ms, refineMs: 0, usedLLM: false,
                          action: post.action)
        default: break
        }
        if llm == .corrections, refiner.isLoaded, CorrectionPrompt.hasCue(raw) {
            t = clock.now
            if let corrected = await correctWithLLM(raw, language: language, style: style, contextTerms: contextTerms) {
                text = corrected
            }
            return Output(text: text, raw: raw, asrMs: asrMs, postMs: postTime.ms, refineMs: (clock.now - t).ms, usedLLM: true)
        }
        // With a streaming polisher, long dictations that contain a list still get their prose polished.
        if llm == .polish, refiner.isLoaded, polisher != nil ? text.split(separator: " ").count >= 6 : Self.worthPolishing(text) {
            t = clock.now
            let polished: String? = if let polisher { await polisher.polish(text) }
                else { try? await refiner.refine(text, language: language, tone: tone) }
            if let polished, !polished.contains("\n") || text.contains("\n") // keep Evoo's own list formatting per app
            {
                text = polished
            }
            return Output(text: text, raw: raw, asrMs: asrMs, postMs: postTime.ms, refineMs: (clock.now - t).ms,
                          usedLLM: true, action: post.action)
        }
        let needsLLM = post.unresolved || language == .hinglish // Hinglish needs romanizing
        if llm == .whenNeeded, needsLLM, !text.isEmpty, refiner.isLoaded {
            t = clock.now
            text = (try? await refiner.refine(text, language: language)) ?? text
            refineTime = clock.now - t
            usedLLM = true
        }
        return Output(text: text, raw: raw, asrMs: asrMs, postMs: postTime.ms, refineMs: refineTime.ms, usedLLM: usedLLM,
                      action: post.action, usedScreenTerms: post.usedScreenTerms)
    }

    /// Short, single-line dictations without anything to fix ("Sounds good.") are pasted as-is: faster,
    /// and nothing for the model to improve. Multi-line (lists) keep Evoo's per-app formatting.
    static func worthPolishing(_ text: String) -> Bool {
        guard !text.isEmpty, !text.contains("\n") else { return false }
        let words = text.split(separator: " ").count
        return words >= 6 || RefinePrompt.needsRefinement(text, language: .english)
    }

    /// LLM deletions on the cleaned transcript, then the usual rules/formatting on the result.
    /// Returns nil if the model's answer wasn't a safe edit (the rule-based result stands).
    public func correctWithLLM(_ raw: String, language: DictationLanguage, style: OutputStyle?,
                               contextTerms: [String] = []) async -> String?
    {
        let cleaned = TextCleaner.clean(raw)
        guard let edited = try? await refiner.correct(cleaned) else { return nil }
        return postProcess(edited, language: language, style: style, contextTerms: contextTerms).text
    }

    /// Everything after ASR except the LLM. Pure and fast. `style` nil = no list/line formatting.
    public struct Processed: Sendable {
        public var text: String
        public var unresolved: Bool
        public var action: DictationCommands.Action?
        public var usedScreenTerms: [String] = []
    }

    public func postProcess(_ raw: String, language: DictationLanguage, style: OutputStyle? = .plain,
                            contextTerms: [String] = []) -> Processed
    {
        // Spoken commands first ("capitalize each word, …", "… press enter", "undo that").
        let command = DictationCommands.parse(TextCleaner.clean(raw))
        // Voice shortcuts are swapped for placeholders so nothing below alters them.
        let masked = Snippets.mask(command.text, snippets: snippets)
        if masked.isWholeDictation {
            return .init(text: masked.text, unresolved: false, action: command.action)
        }
        var text = masked.text
        guard !text.isEmpty else { return .init(text: "", unresolved: false, action: command.action) }
        // The user's dictionary first, then names on screen: "Deva" → "Divya".
        let names = contextTerms.isEmpty ? dictionary : PersonalDictionary(dictionary.terms + contextTerms)
        var usedScreenTerms: [String] = []
        if !names.isEmpty {
            let r = names.applyReporting(text) { Self.knownWords.contains($0) }
            text = r.text
            usedScreenTerms = r.used.filter { contextTerms.contains($0) && !dictionary.terms.contains($0) }
        }
        var result = DictationRules.apply(text) // corrections, fillers, stutters
        if let style {
            result.text = DictationFormatter.format(result.text, style: style) // lists, line breaks, emails
        }
        if language == .english {
            result.text = formatNumbers(result.text) // "four hundred ms" → "400 ms"
        }
        let cased = DictationCommands.applyCasing(command.casing, to: result.text)
        return Processed(text: Snippets.unmask(cased, masked.restore), unresolved: result.unresolved,
                         action: command.action, usedScreenTerms: usedScreenTerms)
    }

    /// Runs NeMo ITN line by line, leaving list markers alone and keeping ordinals used as words
    /// ("first run the tests" must not become "1st run the tests"; "January first" still becomes "January 1").
    func formatNumbers(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            let marker = line.range(of: #"^(- \[ \] |- |• |☐ |\d+\. )"#, options: .regularExpression)
            let prefix = marker.map { String(line[$0]) } ?? ""
            let body = String(line.dropFirst(prefix.count))
            guard !body.isEmpty else { return line }
            // "twenty-eight" → "twenty eight" (the normalizer skips hyphenated numbers).
            var body2 = body.replacingOccurrences(of: #"(?i)\b(twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)-(\w)"#,
                                                  with: "$1 $2", options: .regularExpression)
            var money: [(String, String)] = []
            body2 = maskMoney(body2, into: &money)
            let (masked, restore) = Self.maskOrdinals(body2)
            var out = normalizer.normalizeSentence(masked)
            for (placeholder, word) in restore + money { out = out.replacingOccurrences(of: placeholder, with: word) }
            out = out.replacingOccurrences(of: #"(\d) ?percent\b"#, with: "$1%", options: .regularExpression)
            return prefix + TextCleaner.tidyTimes(out)
        }.joined(separator: "\n")
    }

    static let numberWords = "zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|"
        + "fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|"
        + "thousand|million|billion"

    /// "one thousand two hundred dollars" → "$1,200". The normalizer gets thousands + hundreds + dollars wrong
    /// ("$100200"), so the amount is converted on its own and kept out of its way.
    func maskMoney(_ text: String, into restore: inout [(String, String)]) -> String {
        let pattern = "(?i)\\b((?:(?:" + Self.numberWords + ")(?:\\s+and)?\\s+)*(?:" + Self.numberWords + "))\\s+(dollars?|bucks)\\b"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        var out = text
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(m.range, in: text), let num = Range(m.range(at: 1), in: text) else { continue }
            let digits = normalizer.normalizeSentence(String(text[num])).filter { $0.isNumber || $0 == "." }
            guard let value = Double(digits) else { continue }
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 2
            let placeholder = "evoomoney\(restore.count)x"
            restore.append((placeholder, "$" + (f.string(from: NSNumber(value: value)) ?? digits)))
            out.replaceSubrange(Range(m.range, in: out) ?? whole, with: placeholder)
        }
        return out
    }

    static let months: Set<String> = ["january", "february", "march", "april", "may", "june", "july", "august",
                                      "september", "october", "november", "december"]
    static let ordinalWords: Set<String> = ["first", "second", "third", "firstly", "secondly", "thirdly", "fourth",
                                            "fifth", "last", "next"]

    static let numberContext: Set<String> = [
        "hundred", "thousand", "million", "billion", "twenty", "thirty", "forty", "fifty", "sixty", "seventy",
        "eighty", "ninety", "point", "percent", "dollar", "dollars", "hour", "hours", "minute", "minutes", "day",
        "days", "week", "weeks", "month", "months", "year", "years", "am", "pm", "oclock", "and", "number",
    ]

    static func maskOrdinals(_ text: String) -> (String, [(String, String)]) {
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var restore: [(String, String)] = []
        for i in words.indices {
            let bare = words[i].lowercased().filter(\.isLetter)
            let prev = i > 0 ? words[i - 1].lowercased().filter(\.isLetter) : ""
            let next = i + 1 < words.count ? words[i + 1].lowercased().filter(\.isLetter) : ""
            // "Which one do you mean" must not become "Which 1"; "one hundred", "one hour" still convert.
            let isPronounOne = bare == "one" && !numberContext.contains(prev) && !numberContext.contains(next)
            guard ordinalWords.contains(bare) || isPronounOne else { continue }
            // "twenty first" is a number ("21st"), not the word "first".
            if ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"].contains(prev) { continue }
            let afterOf = i + 2 < words.count ? words[i + 2].lowercased().filter(\.isLetter) : ""
            // A date — "January first", "the first of May" — is left for ITN to write as "January 1".
            if months.contains(prev) || (next == "of" && months.contains(afterOf)) { continue }
            let placeholder = "evooordinal\(restore.count)x"
            let letters = words[i].filter(\.isLetter)
            restore.append((placeholder, letters))
            words[i] = words[i].replacingOccurrences(of: letters, with: placeholder)
        }
        return (words.joined(separator: " "), restore)
    }

    /// Runs a tiny inference so the first real dictation doesn't pay for CoreML/Metal warm-up.
    public static func warmUp(_ engine: SpeechEngine) async {
        _ = try? await engine.transcribe([Float](repeating: 0, count: 16_000), language: .english)
    }
}

extension Duration {
    var ms: Int { Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000) }
}
