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
    }

    private let refiner: LlamaRefiner
    private let normalizer = TextNormalizer.shared
    /// Names and terms to spell right ("Divya"). Set from the user's settings.
    public var dictionary = PersonalDictionary([])

    /// macOS's built-in English word list, used so real words are never "corrected" into names.
    private static let knownWords: Set<String> = {
        guard let text = try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").map { $0.lowercased() })
    }()

    /// Loads the word list off the critical path (takes ~100 ms once).
    public static func preload() {
        DispatchQueue.global(qos: .utility).async { _ = knownWords.count }
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
    public func finish(raw: String, asrMs: Int, language: DictationLanguage, style: OutputStyle?,
                       llm: LLMPolicy) async -> Output
    {
        let clock = ContinuousClock()
        var t = clock.now
        let post = postProcess(raw, language: language, style: style)
        let postTime = clock.now - t

        var text = post.text
        var refineTime: Duration = .zero
        var usedLLM = false
        let needsLLM = post.unresolved || language == .hinglish // Hinglish needs romanizing
        if llm == .whenNeeded, needsLLM, !text.isEmpty, refiner.isLoaded {
            t = clock.now
            text = (try? await refiner.refine(text, language: language)) ?? text
            refineTime = clock.now - t
            usedLLM = true
        }
        return Output(text: text, raw: raw, asrMs: asrMs, postMs: postTime.ms, refineMs: refineTime.ms, usedLLM: usedLLM)
    }

    /// Everything after ASR except the LLM. Pure and fast. `style` nil = no list/line formatting.
    public func postProcess(_ raw: String, language: DictationLanguage, style: OutputStyle? = .plain)
        -> DictationRules.Result
    {
        var text = TextCleaner.clean(raw)
        guard !text.isEmpty else { return .init(text: "", unresolved: false) }
        if !dictionary.isEmpty {
            text = dictionary.apply(text) { Self.knownWords.contains($0) } // "DeVeo" → "Divya"
        }
        var result = DictationRules.apply(text) // corrections, fillers, stutters
        if let style {
            result.text = DictationFormatter.format(result.text, style: style) // lists, line breaks, emails
        }
        if language == .english {
            result.text = formatNumbers(result.text) // "four hundred ms" → "400 ms"
        }
        return result
    }

    /// Runs NeMo ITN line by line, leaving list markers alone and keeping ordinals used as words
    /// ("first run the tests" must not become "1st run the tests"; "January first" still becomes "January 1").
    func formatNumbers(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            let marker = line.range(of: #"^(- \[ \] |- |• |☐ |\d+\. )"#, options: .regularExpression)
            let prefix = marker.map { String(line[$0]) } ?? ""
            let body = String(line.dropFirst(prefix.count))
            guard !body.isEmpty else { return line }
            let (masked, restore) = Self.maskOrdinals(body)
            var out = normalizer.normalizeSentence(masked)
            for (placeholder, word) in restore { out = out.replacingOccurrences(of: placeholder, with: word) }
            return prefix + TextCleaner.tidyTimes(out)
        }.joined(separator: "\n")
    }

    static let months: Set<String> = ["january", "february", "march", "april", "may", "june", "july", "august",
                                      "september", "october", "november", "december"]
    static let ordinalWords: Set<String> = ["first", "second", "third", "firstly", "secondly", "thirdly", "fourth",
                                            "fifth", "last", "next"]

    static func maskOrdinals(_ text: String) -> (String, [(String, String)]) {
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var restore: [(String, String)] = []
        for i in words.indices {
            let bare = words[i].lowercased().filter(\.isLetter)
            guard ordinalWords.contains(bare) else { continue }
            let prev = i > 0 ? words[i - 1].lowercased().filter(\.isLetter) : ""
            let next = i + 1 < words.count ? words[i + 1].lowercased().filter(\.isLetter) : ""
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
