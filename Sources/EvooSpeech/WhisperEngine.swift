import EvooCore
import Foundation
import WhisperKit

/// OpenAI Whisper large-v3 turbo (MIT) on CoreML via WhisperKit (MIT).
/// Multilingual — used for Hindi / Hinglish.
public final class WhisperEngine: SpeechEngine {
    /// A converted model in a local folder (e.g. the Hinglish add-on) instead of the stock download.
    private let modelFolder: URL?
    /// Oriserve's Hinglish models write Roman Hinglish when decoding as "en" (per their model card).
    private let languageOverride: String?

    private let tokenizerFolder: URL?

    public init(modelFolder: URL? = nil, tokenizerFolder: URL? = nil, languageOverride: String? = nil) {
        self.modelFolder = modelFolder
        self.tokenizerFolder = tokenizerFolder
        self.languageOverride = languageOverride
    }

    public let id = ASREngineID.whisper
    private var pipe: WhisperKit?

    public var isLoaded: Bool { pipe != nil }

    public func load(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard pipe == nil else { return }
        try FileManager.default.createDirectory(at: ModelPaths.whisper, withIntermediateDirectories: true)
        progress(0)
        let config = modelFolder.map {
            WhisperKitConfig(modelFolder: $0.path, tokenizerFolder: tokenizerFolder, verbose: false, logLevel: .error,
                             prewarm: true, load: true, download: false)
        } ?? WhisperKitConfig(
            model: WhisperVariant.name,
            downloadBase: ModelPaths.whisper,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: true
        )
        pipe = try await WhisperKit(config)
        progress(1)
    }

    public func transcribe(_ samples: [Float], language: DictationLanguage) async throws -> String {
        guard let pipe else { throw EngineError.notLoaded }
        let options = DecodingOptions(
            task: .transcribe,
            language: languageOverride ?? language.whisperCode,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        // Whisper models tend to drop the first word when speech starts right at the beginning of the clip
        // (measured on the Hinglish model: "Priya ko report…" → "Ko report…"). A little silence in front fixes it.
        let padded = modelFolder == nil ? samples : [Float](repeating: 0, count: 8_000) + samples
        let results = try await pipe.transcribe(audioArray: padded, decodeOptions: options)
        return results.map(\.text).joined(separator: " ")
    }

    public func unload() async {
        await pipe?.unloadModels()
        pipe = nil
    }
}

public enum EngineError: LocalizedError {
    case notLoaded
    public var errorDescription: String? { "Speech model is not loaded yet." }
}
