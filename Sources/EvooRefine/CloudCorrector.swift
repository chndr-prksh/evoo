import EvooCore
import Foundation

/// Optional, opt-in: self-correction by a hosted open-weight model (Llama/Qwen on Groq, Cerebras, …)
/// through the OpenAI-compatible chat API those providers share. Same deletion-only format as the local
/// model (`CorrectionPrompt`), so the answer is a few tokens and can't add or change words.
///
/// Every call has a hard deadline: if the answer isn't back in time, the caller keeps the rule-based
/// result, so dictation never waits longer than the budget.
public final class CloudCorrector: @unchecked Sendable {
    public enum Provider: String, CaseIterable, Sendable {
        case groq, cerebras, together, fireworks, openrouter, deepinfra

        public var baseURL: URL {
            let url = switch self {
            case .groq: "https://api.groq.com/openai/v1"
            case .cerebras: "https://api.cerebras.ai/v1"
            case .together: "https://api.together.xyz/v1"
            case .fireworks: "https://api.fireworks.ai/inference/v1"
            case .openrouter: "https://openrouter.ai/api/v1"
            case .deepinfra: "https://api.deepinfra.com/v1/openai"
            }
            return URL(string: url)!
        }

        /// A fast open-weight default; any model the provider serves can be passed instead.
        public var defaultModel: String {
            switch self {
            case .groq: "llama-3.1-8b-instant"
            case .cerebras: "llama3.1-8b"
            case .together: "meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo"
            case .fireworks: "accounts/fireworks/models/llama-v3p1-8b-instruct"
            case .openrouter: "meta-llama/llama-3.1-8b-instruct"
            case .deepinfra: "meta-llama/Meta-Llama-3.1-8B-Instruct"
            }
        }
    }

    public let provider: Provider
    public let model: String
    private let apiKey: String
    private let session: URLSession

    public init(provider: Provider, apiKey: String, model: String? = nil) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model ?? provider.defaultModel
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 2
        config.timeoutIntervalForRequest = 5
        session = URLSession(configuration: config)
    }

    /// Opens the HTTPS connection ahead of time (call when fn goes down) so the real request skips the
    /// TCP + TLS handshake — about 75–175 ms from a US home connection.
    public func warmUp() {
        var request = URLRequest(url: provider.baseURL.appendingPathComponent("models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        session.dataTask(with: request).resume()
    }

    /// The corrected text, or nil if the model found nothing safe to delete, failed, or missed the deadline.
    public func correct(_ text: String, deadline: Duration = .milliseconds(300)) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { [self] in (try? await answer(for: text)).flatMap { self.apply($0, to: text) } }
            group.addTask { try? await Task.sleep(for: deadline); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Model IDs this key can use (the provider's /models list).
    public func availableModels() async throws -> [String] {
        var request = URLRequest(url: provider.baseURL.appendingPathComponent("models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CloudError.http((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data.prefix(300), as: UTF8.self))
        }
        struct List: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        return try JSONDecoder().decode(List.self, from: data).data.map(\.id).sorted()
    }

    /// Raw answer text ("3-4", "none") — exposed for benchmarking.
    public func answer(for text: String) async throws -> String {
        var messages: [[String: String]] = [["role": "system", "content": CorrectionPrompt.system]]
        for ex in CorrectionPrompt.examples {
            messages.append(["role": "user", "content": CorrectionPrompt.numbered(ex.text)])
            messages.append(["role": "assistant", "content": ex.answer])
        }
        messages.append(["role": "user", "content": CorrectionPrompt.numbered(text)])
        var body: [String: Any] = ["model": model, "messages": messages, "temperature": 0, "max_tokens": 12]
        if model.contains("gpt-oss") {
            // Reasoning models spend tokens thinking first; keep it minimal and leave room for the answer.
            body["reasoning_effort"] = "low"
            body["max_tokens"] = 256
        } else if model.lowercased().contains("qwen3") {
            // Qwen3 can skip its thinking phase entirely — essential for a sub-300 ms answer.
            body["reasoning_effort"] = "none"
        }

        var request = URLRequest(url: provider.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CloudError.http((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data.prefix(300), as: UTF8.self))
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    private func apply(_ answer: String, to text: String) -> String? {
        guard let indices = CorrectionPrompt.parse(answer) else { return nil }
        return CorrectionPrompt.apply(indices, to: text)
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }

        let choices: [Choice]
    }

    public enum CloudError: LocalizedError {
        case http(Int, String)
        public var errorDescription: String? {
            if case let .http(code, body) = self { "HTTP \(code): \(body)" } else { nil }
        }
    }
}
