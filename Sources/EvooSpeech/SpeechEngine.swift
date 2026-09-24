import EvooCore
import FluidAudio
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

/// Owns the speech engines and their loading, so that:
///  • each model loads once, however often the user switches language;
///  • dictation never waits on a load — callers ask `ready(_:)` and get nil while it's preparing;
///  • the old engine stays usable until the new one is ready (switching back is instant).
@MainActor
public final class SpeechEngines {
    private var engines: [ASREngineID: SpeechEngine] = [:]
    private var loads: [ASREngineID: Task<Void, Error>] = [:]
    /// `.v3` (0.6B, accurate) or `.tdtCtc110m` (110M, ~2× faster, weaker on names).
    public private(set) var parakeetVersion: AsrModelVersion

    public init(parakeetVersion: AsrModelVersion = .v3) {
        self.parakeetVersion = parakeetVersion
    }

    /// Switches the English model. Dictation reports "preparing" until the caller has prepared the new one.
    public func setParakeetVersion(_ version: AsrModelVersion) {
        guard version != parakeetVersion else { return }
        parakeetVersion = version
        if let old = engines[.parakeet], loads[.parakeet] == nil {
            engines[.parakeet] = nil
            Task { await old.unload() }
        }
    }

    /// The engine if it's loaded and can transcribe right now.
    public func ready(_ id: ASREngineID) -> SpeechEngine? {
        guard let engine = engines[id], engine.isLoaded else { return nil }
        return engine
    }

    public func isPreparing(_ id: ASREngineID) -> Bool { loads[id] != nil }

    /// Loads `id` if needed (joining a load already in flight) and warms it up.
    public func prepare(_ id: ASREngineID) async throws {
        if ready(id) != nil { return }
        if let inFlight = loads[id] { return try await inFlight.value }
        let engine = engines[id] ?? make(id)
        engines[id] = engine
        let task = Task { @MainActor in
            defer { self.loads[id] = nil }
            try await engine.load { _ in }
            await DictationPipeline.warmUp(engine) // first dictation shouldn't pay CoreML warm-up
        }
        loads[id] = task
        try await task.value
    }

    /// Frees every loaded engine except `keep` (Whisper alone is ~1.5 GB of RAM).
    public func unload(except keep: Set<ASREngineID>) {
        for (id, engine) in engines where !keep.contains(id) && loads[id] == nil {
            engines[id] = nil
            Task { await engine.unload() }
        }
    }

    func make(_ id: ASREngineID) -> SpeechEngine {
        switch id {
        case .parakeet: ParakeetEngine(version: parakeetVersion)
        case .whisper: WhisperEngine()
        }
    }
}
