import EvooCore
import EvooRefine
import FluidAudio
import Foundation

/// Audio → final text, with per-stage timings. Shared by the app and `evoo-cli`.
///
///   ASR ─▶ TextCleaner ─▶ number formatting (NeMo ITN) ─▶ DictationRules ─▶ LLM (only if still needed)
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

    public init(refiner: LlamaRefiner) {
        self.refiner = refiner
    }

    public func run(samples: [Float], engine: SpeechEngine, language: DictationLanguage,
                    llm: LLMPolicy) async throws -> Output
    {
        let clock = ContinuousClock()
        var t = clock.now
        let raw = try await engine.transcribe(samples, language: language)
        let asr = clock.now - t

        t = clock.now
        let post = postProcess(raw, language: language)
        let postTime = clock.now - t

        var text = post.text
        var refineTime: Duration = .zero
        var usedLLM = false
        let needsLLM = post.unresolved || language != .english
        if llm == .whenNeeded, needsLLM, !text.isEmpty, refiner.isLoaded {
            t = clock.now
            text = (try? await refiner.refine(text, language: language)) ?? text
            refineTime = clock.now - t
            usedLLM = true
        }
        return Output(text: text, raw: raw, asrMs: asr.ms, postMs: postTime.ms, refineMs: refineTime.ms, usedLLM: usedLLM)
    }

    /// Everything after ASR except the LLM. Pure and fast.
    public func postProcess(_ raw: String, language: DictationLanguage) -> DictationRules.Result {
        var text = TextCleaner.clean(raw)
        guard !text.isEmpty else { return .init(text: "", unresolved: false) }
        if language == .english {
            text = normalizer.normalizeSentence(text) // "four hundred ms" → "400 ms"
        }
        return DictationRules.apply(text)
    }

    /// Runs a tiny inference so the first real dictation doesn't pay for CoreML/Metal warm-up.
    public static func warmUp(_ engine: SpeechEngine) async {
        _ = try? await engine.transcribe([Float](repeating: 0, count: 16_000), language: .english)
    }
}

extension Duration {
    var ms: Int { Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000) }
}
