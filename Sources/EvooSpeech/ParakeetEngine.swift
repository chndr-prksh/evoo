import EvooCore
import FluidAudio
import Foundation

/// NVIDIA Parakeet TDT 0.6B v3 (CC-BY-4.0) on CoreML / Neural Engine via FluidAudio (Apache-2.0).
/// Fastest option; English + 24 other European languages.
public final class ParakeetEngine: SpeechEngine {
    public let version: AsrModelVersion

    public init(version: AsrModelVersion = .v3) {
        self.version = version
    }

    public let id = ASREngineID.parakeet
    private var manager: AsrManager?

    public var isLoaded: Bool { manager != nil }

    public func load(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard manager == nil else { return }
        progress(0)
        let models = try await AsrModels.downloadAndLoad(to: ModelPaths.parakeet, version: version)
        let manager = AsrManager()
        try await manager.loadModels(models)
        self.manager = manager
        progress(1)
    }

    public func transcribe(_ samples: [Float], language: DictationLanguage) async throws -> String {
        guard let manager else { throw EngineError.notLoaded }
        var state = TdtDecoderState.make(decoderLayers: version.decoderLayers)
        // v3 speaks 25 languages and can drift into Cyrillic on short phrases ("Ол кабс" for "All caps").
        // Telling it the language restricts decoding to Latin-script tokens.
        let hint: Language? = language == .english ? .english : nil
        return try await manager.transcribe(samples, decoderState: &state, language: hint).text
    }

    /// Full transcription with word timings, for files and subtitles.
    public func transcribeDetailed(_ samples: [Float]) async throws -> (text: String, timings: [Subtitles.Timed]) {
        guard let manager else { throw EngineError.notLoaded }
        var state = TdtDecoderState.make(decoderLayers: version.decoderLayers)
        let result = try await manager.transcribe(samples, decoderState: &state, language: .english)
        let timings = (result.tokenTimings ?? []).map {
            Subtitles.Timed(text: $0.token, start: $0.startTime, end: $0.endTime)
        }
        return (result.text, timings)
    }

    public func unload() async {
        await manager?.cleanup()
        manager = nil
    }
}
