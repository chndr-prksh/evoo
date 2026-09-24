import EvooCore
import Foundation
import WhisperKit

/// OpenAI Whisper large-v3 turbo (MIT) on CoreML via WhisperKit (MIT).
/// Multilingual — used for Hindi / Hinglish.
final class WhisperEngine: SpeechEngine {
    let id = ASREngineID.whisper
    private var pipe: WhisperKit?

    var isLoaded: Bool { pipe != nil }

    func load(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard pipe == nil else { return }
        try FileManager.default.createDirectory(at: ModelPaths.whisper, withIntermediateDirectories: true)
        progress(0)
        let config = WhisperKitConfig(
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

    func transcribe(_ samples: [Float], language: DictationLanguage) async throws -> String {
        guard let pipe else { throw EngineError.notLoaded }
        let options = DecodingOptions(
            task: .transcribe,
            language: language.whisperCode,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ")
    }

    func unload() async {
        await pipe?.unloadModels()
        pipe = nil
    }
}

enum EngineError: LocalizedError {
    case notLoaded
    var errorDescription: String? { "Speech model is not loaded yet." }
}
