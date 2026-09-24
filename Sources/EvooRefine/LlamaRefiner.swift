import EvooCore
import Foundation
import llama

/// Turns a raw transcript into what the speaker meant, using a small open-weight LLM
/// (Qwen3, Apache-2.0) running locally through llama.cpp with Metal.
///
/// All llama.cpp calls happen on one serial queue; the C context is not thread-safe.
public final class LlamaRefiner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "evoo.llama", qos: .userInitiated)
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    public private(set) var loadedModel: RefinerModel?
    /// Tokens of the static prompt prefix currently held in the KV cache.
    private var cachedPrefix: [llama_token] = []

    private static let contextSize: UInt32 = 4096

    static let backendReady: Void = {
        // Silence llama.cpp logging unless EVOO_LLAMA_LOG is set.
        if ProcessInfo.processInfo.environment["EVOO_LLAMA_LOG"] == nil { llama_log_set({ _, _, _ in }, nil) }
        llama_backend_init()
    }()

    public init() {}

    public var isLoaded: Bool { queue.sync { context != nil } }

    /// Loads the model and pre-evaluates the prompt for `language`, so the first dictation is fast too.
    public func load(_ which: RefinerModel, language: DictationLanguage = .english) async throws {
        let path = ModelPaths.refiner(which).path
        guard FileManager.default.fileExists(atPath: path) else { throw RefinerError.modelMissing }
        try await run { [self] in
            _ = Self.backendReady
            if loadedModel == which, context != nil {
                return try primePrefix(RefinePrompt.prefix(language: language))
            }
            freeAll()

            var mparams = llama_model_default_params()
            mparams.n_gpu_layers = 99 // everything on Metal
            guard let m = llama_model_load_from_file(path, mparams) else { throw RefinerError.loadFailed }

            var cparams = llama_context_default_params()
            cparams.n_ctx = Self.contextSize
            cparams.n_batch = Self.contextSize
            cparams.no_perf = true
            guard let c = llama_init_from_model(m, cparams) else {
                llama_model_free(m)
                throw RefinerError.loadFailed
            }

            let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())
            llama_sampler_chain_add(chain, llama_sampler_init_greedy()) // deterministic output

            model = m
            context = c
            vocab = llama_model_get_vocab(m)
            sampler = chain
            loadedModel = which
            try primePrefix(RefinePrompt.prefix(language: language))
        }
    }

    public func unload() {
        queue.sync { freeAll() }
    }

    public func refine(_ transcript: String, language: DictationLanguage) async throws -> String {
        let raw = try await run { [self] in
            try primePrefix(RefinePrompt.prefix(language: language))
            let suffix = RefinePrompt.suffix(transcript: transcript, thinkBlock: loadedModel?.usesThinkBlock ?? true)
            let budget = RefinePrompt.maxTokens(forInputTokens: tokenize(transcript, vocab: vocab!, addSpecial: false).count)
            return try generate(suffix: suffix, maxTokens: budget)
        }
        return RefinePrompt.accept(refined: raw, input: transcript, language: language) ?? transcript
    }

    /// Self-correction as deletions (see `CorrectionPrompt`). Returns nil when the model's answer
    /// isn't a safe edit, so the caller keeps the rule-based result.
    public func correct(_ text: String) async throws -> String? {
        let answer = try await run { [self] in
            try primePrefix(CorrectionPrompt.prefix)
            // The answer is a few numbers ("3-4", "none"), so a tiny budget keeps it fast.
            return try generate(suffix: CorrectionPrompt.suffix(text, thinkBlock: loadedModel?.usesThinkBlock ?? true),
                                maxTokens: 12)
        }
        guard let indices = CorrectionPrompt.parse(answer) else { return nil }
        return CorrectionPrompt.apply(indices, to: text)
    }

    // MARK: - llama.cpp

    /// Ensures the KV cache holds exactly `prefix`, evaluating it only when it changed (e.g. new language).
    private func primePrefix(_ prefix: String) throws {
        guard let context, let vocab else { throw RefinerError.notLoaded }
        let tokens = tokenize(prefix, vocab: vocab, addSpecial: true)
        let memory = llama_get_memory(context)
        if tokens == cachedPrefix {
            llama_memory_seq_rm(memory, 0, Int32(tokens.count), -1) // drop the previous dictation
            return
        }
        llama_memory_clear(memory, true)
        cachedPrefix = []
        try decode(tokens)
        cachedPrefix = tokens
    }

    private func generate(suffix: String, maxTokens: Int) throws -> String {
        guard let context, let vocab, let sampler else { throw RefinerError.notLoaded }
        llama_sampler_reset(sampler)

        let tokens = tokenize(suffix, vocab: vocab, addSpecial: false)
        let room = Int(Self.contextSize) - cachedPrefix.count - tokens.count - 1
        guard !tokens.isEmpty, room > 32 else { throw RefinerError.inputTooLong }
        try decode(tokens)

        var bytes: [UInt8] = []
        var piece = [CChar](repeating: 0, count: 256)
        for _ in 0 ..< min(maxTokens, room) {
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            let n = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            if n > 0 { bytes.append(contentsOf: piece[0 ..< Int(n)].map { UInt8(bitPattern: $0) }) }
            guard llama_decode(context, llama_batch_get_one(&token, 1)) == 0 else { throw RefinerError.decodeFailed }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func decode(_ tokens: [llama_token]) throws {
        guard let context else { throw RefinerError.notLoaded }
        var tokens = tokens
        let status = tokens.withUnsafeMutableBufferPointer { buf in
            llama_decode(context, llama_batch_get_one(buf.baseAddress, Int32(buf.count)))
        }
        guard status == 0 else { throw RefinerError.decodeFailed }
    }

    private func tokenize(_ text: String, vocab: OpaquePointer, addSpecial: Bool) -> [llama_token] {
        let utf8Count = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(utf8Count) + 8)
        var n = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), addSpecial, true)
        if n < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-n))
            n = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), addSpecial, true)
        }
        return n > 0 ? Array(tokens.prefix(Int(n))) : []
    }

    private func freeAll() {
        if let sampler { llama_sampler_free(sampler) }
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        sampler = nil
        context = nil
        model = nil
        vocab = nil
        loadedModel = nil
        cachedPrefix = []
    }

    private func run<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async { cont.resume(with: Result { try work() }) }
        }
    }

    deinit { freeAll() }
}

public enum RefinerError: LocalizedError {
    case modelMissing, loadFailed, notLoaded, inputTooLong, decodeFailed

    public var errorDescription: String? {
        switch self {
        case .modelMissing: "Refinement model not downloaded."
        case .loadFailed: "Couldn't load the refinement model."
        case .notLoaded: "Refinement model not loaded."
        case .inputTooLong: "Dictation too long to refine."
        case .decodeFailed: "Refinement model failed."
        }
    }
}
