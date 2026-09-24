import EvooCore
import FluidAudio
import Foundation

/// NVIDIA Parakeet TDT 0.6B v3 (CC-BY-4.0) on CoreML / Neural Engine via FluidAudio (Apache-2.0).
/// Fastest option; English + 24 other European languages.
final class ParakeetEngine: SpeechEngine {
    let id = ASREngineID.parakeet
    private var manager: AsrManager?

    var isLoaded: Bool { manager != nil }

    func load(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard manager == nil else { return }
        progress(0)
        let models = try await AsrModels.downloadAndLoad(to: ModelPaths.parakeet, version: .v3)
        let manager = AsrManager()
        try await manager.loadModels(models)
        self.manager = manager
        progress(1)
    }

    func transcribe(_ samples: [Float], language _: DictationLanguage) async throws -> String {
        guard let manager else { throw EngineError.notLoaded }
        var state = TdtDecoderState.make()
        return try await manager.transcribe(samples, decoderState: &state).text
    }

    func unload() async {
        await manager?.cleanup()
        manager = nil
    }
}
