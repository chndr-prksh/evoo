import EvooCore
import Foundation

/// A local speech-to-text model. The rest of Evoo only talks to this protocol.
public protocol SpeechEngine: AnyObject {
    var id: ASREngineID { get }
    var isLoaded: Bool { get }
    /// Downloads (first run only) and loads the model. Call once and keep it warm.
    func load(progress: @escaping @Sendable (Double) -> Void) async throws
    /// `samples`: 16 kHz mono Float32.
    func transcribe(_ samples: [Float], language: DictationLanguage) async throws -> String
    func unload() async
}

/// Owns one engine at a time so only one ASR model sits in RAM (8 GB Macs).
@MainActor
public final class SpeechEngines {
    public private(set) var current: SpeechEngine?

    public init() {}

    public func engine(for id: ASREngineID) -> SpeechEngine {
        if let current, current.id == id { return current }
        let engine: SpeechEngine = switch id {
        case .parakeet: ParakeetEngine()
        case .whisper: WhisperEngine()
        }
        let previous = current
        current = engine
        Task { await previous?.unload() }
        return engine
    }
}
