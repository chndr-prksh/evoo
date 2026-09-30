import EvooCore
import Foundation

/// Starts transcribing while fn is still held, whenever the speaker pauses.
///
/// People almost always pause before releasing fn. If nothing but silence was recorded after the pause,
/// the speech is identical to what was already sent to the model (trailing silence is trimmed), so the
/// result is reused and the text is ready the instant fn goes up. If they kept talking, it's discarded.
@MainActor
public final class SpeculativeTranscriber {
    private var job: (speech: Range<Int>, task: Task<String, Error>)?
    private var running = false

    public private(set) var reuseCount = 0
    /// Called with each speculative transcript (to start polishing it before fn goes up), and whether it was
    /// taken at a pause (then the last sentence is likely finished too).
    public var onResult: ((String, Bool) -> Void)?
    private var lastStart = ContinuousClock.now

    public init() {}

    public func reset() {
        job = nil
    }

    /// Call periodically while recording with everything recorded so far.
    /// `every`: also transcribe this often while the person keeps talking (no pause needed), so finished sentences
    /// can be polished during fluent speech — people often don't pause 0.3 s between sentences.
    public func consider(_ samples: [Float], engine: SpeechEngine, every: Duration? = nil) {
        guard !running, samples.count > 8_000 else { return }
        let paused = AudioStats.endsInPause(samples, seconds: 0.3)
        guard paused || every.map({ ContinuousClock.now - lastStart >= $0 }) == true,
              let speech = AudioStats.speechRange(samples), speech != job?.speech else { return }
        running = true
        lastStart = ContinuousClock.now
        let clip = Array(samples[speech])
        job = (speech, Task { [weak self] in
            defer { Task { @MainActor in self?.running = false } }
            let text = try await engine.transcribe(clip, language: .english)
            await MainActor.run { self?.onResult?(text, paused) }
            return text
        })
    }

    /// The transcript for the final recording, reusing the speculative one when the speech is unchanged.
    public func transcript(for samples: [Float], engine: SpeechEngine) async throws -> (text: String, reused: Bool) {
        guard let speech = AudioStats.speechRange(samples) else { return ("", false) }
        if let job, job.speech == speech {
            reuseCount += 1
            return (try await job.task.value, true)
        }
        return (try await engine.transcribe(Array(samples[speech]), language: .english), false)
    }
}
