import EvooCore
import Foundation
import llama

/// Runs the small tool-calling model (FunctionGemma 270M, GGUF) on llama.cpp: what you said in, tool calls out.
/// It has its own model and memory, so the polish model stays loaded beside it. The long list of tools at the
/// start of the prompt is read once and kept; each request only pays for its own few words.
public final class ToolCaller: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.evoo.tools", qos: .userInitiated)
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    private var cachedPrefix: [llama_token] = []
    private static let contextSize: UInt32 = 8192

    public init() {}

    private let loadedLock = NSLock()
    private var loaded = false
    public var isLoaded: Bool { loadedLock.withLock { loaded } }
    /// How many tokens the tool list takes (for measuring).
    public private(set) var prefixTokens = 0

    /// Loads the model and reads the tool list (`prefix`) once.
    public func load(path: String, prefix: String) async throws {
        try await run { [self] in
            free()
            _ = LlamaRefiner.backendReady
            var mparams = llama_model_default_params()
            mparams.n_gpu_layers = 99
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
            llama_sampler_chain_add(chain, llama_sampler_init_greedy()) // the same request always gives the same action
            model = m; context = c; vocab = llama_model_get_vocab(m); sampler = chain
            let tokens = tokenize(prefix, addSpecial: true)
            try decode(tokens)
            cachedPrefix = tokens
            prefixTokens = tokens.count
            loadedLock.withLock { loaded = true }
        }
    }

    /// The model's raw answer for one request (parse it with `ToolCall.parse`).
    public func complete(_ text: String, maxTokens: Int = 160) async throws -> String {
        try await run { [self] in
            guard let context, let vocab, let sampler else { throw RefinerError.notLoaded }
            llama_memory_seq_rm(llama_get_memory(context), 0, Int32(cachedPrefix.count), -1) // forget the last request
            llama_sampler_reset(sampler)
            try decode(tokenize(ToolCall.userTurn(text), addSpecial: false))
            var bytes: [UInt8] = []
            var piece = [CChar](repeating: 0, count: 256)
            for _ in 0 ..< maxTokens {
                var token = llama_sampler_sample(sampler, context, -1)
                if llama_vocab_is_eog(vocab, token) { break }
                // special = true: the call markers (<start_function_call>, <escape>) are special tokens and must be kept.
                let n = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, true)
                if n > 0 { bytes.append(contentsOf: piece[0 ..< Int(n)].map { UInt8(bitPattern: $0) }) }
                let so = String(decoding: bytes, as: UTF8.self)
                if so.hasSuffix("<start_function_response>") || so.hasSuffix("<end_of_turn>") { break }
                guard llama_decode(context, llama_batch_get_one(&token, 1)) == 0 else { throw RefinerError.decodeFailed }
            }
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    public func unload() { queue.sync { free() } }

    private func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async { cont.resume(with: Result { try work() }) }
        }
    }

    private func decode(_ tokens: [llama_token]) throws {
        guard let context, !tokens.isEmpty else { return }
        var tokens = tokens
        let status = tokens.withUnsafeMutableBufferPointer { llama_decode(context, llama_batch_get_one($0.baseAddress, Int32($0.count))) }
        guard status == 0 else { throw RefinerError.decodeFailed }
    }

    private func tokenize(_ text: String, addSpecial: Bool) -> [llama_token] {
        guard let vocab else { return [] }
        let count = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(count) + 8)
        var n = llama_tokenize(vocab, text, count, &tokens, Int32(tokens.count), addSpecial, true)
        if n < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-n))
            n = llama_tokenize(vocab, text, count, &tokens, Int32(tokens.count), addSpecial, true)
        }
        return n > 0 ? Array(tokens.prefix(Int(n))) : []
    }

    private func free() {
        loadedLock.withLock { loaded = false }
        if let sampler { llama_sampler_free(sampler) }
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        sampler = nil; context = nil; model = nil; vocab = nil
        cachedPrefix = []
    }
}
