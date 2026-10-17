import Foundation

/// Open-weight LLMs used to refine transcripts. All Apache-2.0, run locally via llama.cpp.
/// Files are pinned to an exact Hugging Face revision and verified by SHA-256.
public enum RefinerModel: String, CaseIterable, Codable, Sendable {
    /// Evoo's own polish model: Qwen3-0.6B fine-tuned on dictation (huggingface.co/e2chndr/evoo-ai-v1).
    case evooAI_v1
    case qwen3_0_6b
    case qwen3_1_7b
    case qwen3_4b

    public var title: String {
        switch self {
        case .evooAI_v1: "Evoo AI v1 — fine-tuned for dictation (≈0.6 GB)"
        case .qwen3_0_6b: "Qwen3 0.6B — fastest (≈0.6 GB)"
        case .qwen3_1_7b: "Qwen3 1.7B — fast (≈1.1 GB, fits 8 GB Macs)"
        case .qwen3_4b: "Qwen3 4B Instruct — better (≈2.5 GB, 16 GB+ RAM)"
        }
    }

    public var fileName: String {
        switch self {
        case .evooAI_v1: "evoo-ai-v1-q8_0.gguf"
        case .qwen3_0_6b: "Qwen3-0.6B-Q8_0.gguf"
        case .qwen3_1_7b: "Qwen3-1.7B-Q4_K_M.gguf"
        case .qwen3_4b: "Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
        }
    }

    var repo: String {
        switch self {
        case .evooAI_v1: "e2chndr/evoo-ai-v1"
        case .qwen3_0_6b: "unsloth/Qwen3-0.6B-GGUF"
        case .qwen3_1_7b: "unsloth/Qwen3-1.7B-GGUF"
        case .qwen3_4b: "unsloth/Qwen3-4B-Instruct-2507-GGUF"
        }
    }

    var revision: String {
        switch self {
        case .evooAI_v1: "669c358a004f84546d86740b58bd20eb715efcec"
        case .qwen3_0_6b: "50968a4468ef4233ed78cd7c3de230dd1d61a56b"
        case .qwen3_1_7b: "d7f544eead698dbd1f15126ef60b45a1e1933222"
        case .qwen3_4b: "a06e946bb6b655725eafa393f4a9745d460374c9"
        }
    }

    public var sha256: String {
        switch self {
        case .evooAI_v1: "e05b1c95222d3a5650a8e57ab015189baa75bfbebabe282848ce020970249831"
        case .qwen3_0_6b: "e150ed544dfe6016930c026a93913a5e3184181ebfe6ab2223ae01dd0491784c"
        case .qwen3_1_7b: "b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897"
        case .qwen3_4b: "3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597"
        }
    }

    public var sizeBytes: Int64 {
        switch self {
        case .evooAI_v1: 639_447_168
        case .qwen3_0_6b: 639_447_744
        case .qwen3_1_7b: 1_107_409_472
        case .qwen3_4b: 2_497_281_120
        }
    }

    public var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(fileName)")!
    }

    public var license: String {
        self == .evooAI_v1 ? "Evoo AI (fine-tuned from Qwen3 by Alibaba) — Apache-2.0" : "Qwen3 (Alibaba) — Apache-2.0"
    }

    /// Fine-tuned on dictation: asked with a one-line instruction instead of the rules and worked examples,
    /// and run after Evoo's rules on every dictation (it was measured best that way).
    public var isFineTuned: Bool { self == .evooAI_v1 }

    /// Big enough to use the text before a dictation to understand its topic.
    public var readsContext: Bool { self == .qwen3_1_7b || self == .qwen3_4b }

    /// Hybrid-thinking Qwen3 models need an empty <think> block to answer directly.
    public var usesThinkBlock: Bool { self != .qwen3_4b }
}

/// WhisperKit CoreML variant: large-v3 turbo, quantized to fit 8 GB Macs.
public enum WhisperVariant {
    public static let name = "openai_whisper-large-v3-v20240930_turbo_632MB"
}

public enum ModelPaths {
    /// ~/Library/Application Support/Evoo/Models
    public static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Evoo/Models", isDirectory: true)
    }

    /// A model file to use instead of the downloaded one (evoo-cli --model-file, for testing a new model).
    nonisolated(unsafe) public static var refinerOverride: URL?

    public static func refiner(_ model: RefinerModel) -> URL {
        refinerOverride ?? root.appendingPathComponent("llm/\(model.fileName)")
    }

    public static var whisper: URL { root.appendingPathComponent("whisper", isDirectory: true) }
    public static var parakeet: URL { root.appendingPathComponent("parakeet", isDirectory: true) }
}
