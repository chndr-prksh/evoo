import EvooCore
import Foundation

/// Transcribes a long dictation in pieces while fn is still held, so releasing fn only leaves the last few
/// seconds to do.
///
/// Whenever the speaker pauses, the stretch since the last committed point is either
///   - committed (≥ `minSegment` of audio): transcribed once and never again, or
///   - speculated (shorter): transcribed, and reused at release if nothing but silence followed.
/// Very long stretches without a pause are cut at the quietest moment near the end.
@MainActor
public final class StreamingDictation {
    /// Pieces are cut only at a real break (not a breath mid-sentence) and only once they're sentence-sized:
    /// a piece is transcribed without the words around it, so short pieces lose accuracy ("updated. File.").
    public static let minSegment = 8.0 // seconds
    public static let maxSegment = 25.0
    public static let segmentPause = 0.6
    /// Up to this long, the final text comes from one pass over the whole recording (most accurate); the
    /// pieces are only used to start polishing early.
    public static let wholeClipLimit = 45.0

    private var committed: [String] = []
    private var committedEnd = 0
    private var busy: Task<Void, Never>?
    private var tail: (speech: Range<Int>, start: Int, task: Task<String, Error>)?
    /// Called with the latest stretches each time one is committed (to start polishing them).
    /// The Bool is true when the text starts mid-dictation (its first sentence may be cut).
    public var onCommit: ((String, Bool) -> Void)?

    public private(set) var committedSeconds = 0.0

    public init() {}

    public func reset() {
        whole.reset()
        committed = []
        committedEnd = 0
        busy = nil
        tail = nil
        committedSeconds = 0
    }

    /// The transcript of everything committed so far.
    public var textSoFar: String { committed.joined(separator: " ") }

    /// The last few committed stretches — enough to polish what was just said without re-processing a
    /// multi-minute dictation on every pause.
    public func recentText(stretches: Int = 3) -> String { committed.suffix(stretches).joined(separator: " ") }

    /// Where the not-yet-committed audio starts (pass `recording[committedSamples...]` to `consider`).
    public var committedSamples: Int { committedEnd }

    /// Call periodically while recording with everything recorded so far.
    public func consider(_ samples: [Float], engine: SpeechEngine) {
        guard samples.count > committedEnd else { return }
        consider(recent: Array(samples[committedEnd...]), from: committedEnd, engine: engine)
    }

    /// Call periodically while recording with the audio from `committedSamples` on.
    public func consider(recent pending: [Float], from offset: Int, engine: SpeechEngine) {
        guard busy == nil, offset == committedEnd, pending.count > 8_000 else { return }
        let rate = 16_000.0
        let seconds = Double(pending.count) / rate
        let paused = AudioStats.endsInPause(pending, seconds: Self.segmentPause)
        let breath = AudioStats.endsInPause(pending, seconds: 0.35)
        guard breath || seconds >= Self.maxSegment else { return }

        if seconds >= Self.minSegment, paused || seconds >= Self.maxSegment {
            // Commit up to the pause (or the quietest point near the end of a very long stretch).
            let cut = paused ? pending.count : Self.quietestPoint(pending, within: Int(3 * rate))
            let end = committedEnd + cut
            let clip = Array(pending[0 ..< cut])
            committedEnd = end
            tail = nil
            busy = Task { [weak self] in
                let text = (try? await Self.transcribe(clip, engine: engine)) ?? ""
                guard let self else { return }
                if !text.isEmpty { self.committed.append(text) }
                self.committedSeconds = Double(end) / rate
                self.busy = nil
                self.onCommit?(self.recentText(), self.committed.count > 3)
            }
        } else if let speech = AudioStats.speechRange(pending), speech != tail?.speech || tail?.start != committedEnd {
            // Short stretch: speculate, reuse at release if nothing more is said.
            let clip = Array(pending[speech])
            let start = committedEnd
            let task = Task { try await engine.transcribe(clip, language: .english) }
            tail = (speech, start, task)
            busy = Task { [weak self] in
                _ = try? await task.value
                self?.busy = nil
            }
        }
    }

    /// Whole-recording speculation for dictations up to `wholeClipLimit`: call at each tick with everything
    /// recorded so far (it only transcribes at a pause, and reuses the result at release if nothing changed).
    public func considerWhole(_ samples: [Float], engine: SpeechEngine) {
        guard Double(samples.count) / 16_000 <= Self.wholeClipLimit else { return }
        whole.consider(samples, engine: engine)
    }

    private let whole = SpeculativeTranscriber()

    /// The whole transcript. Up to `wholeClipLimit`: one pass over the whole recording (reused when it was
    /// already done during the last pause). Longer: committed pieces plus the rest.
    public func finish(_ samples: [Float], engine: SpeechEngine) async throws -> (text: String, reused: Bool) {
        if Double(samples.count) / 16_000 <= Self.wholeClipLimit {
            return try await whole.transcript(for: samples, engine: engine)
        }
        await busy?.value
        let rest = committedEnd < samples.count ? Array(samples[committedEnd...]) : []
        var last = ""
        var reused = false
        if let speech = AudioStats.speechRange(rest) {
            if let tail, tail.start == committedEnd, tail.speech == speech {
                last = try await tail.task.value
                reused = true
            } else {
                last = try await engine.transcribe(Array(rest[speech]), language: .english)
            }
        } else {
            reused = !committed.isEmpty
        }
        let text = (committed + [last]).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: " ")
        return (text, reused)
    }

    private static func transcribe(_ clip: [Float], engine: SpeechEngine) async throws -> String {
        guard let speech = AudioStats.speechRange(clip) else { return "" }
        return try await engine.transcribe(Array(clip[speech]), language: .english)
    }

    /// Index of the quietest 100 ms in the last `within` samples (to cut a long stretch between words).
    static func quietestPoint(_ samples: [Float], within: Int) -> Int {
        let window = 1_600
        let from = max(0, samples.count - within)
        var best = samples.count, bestEnergy = Float.greatestFiniteMagnitude
        var i = from
        while i + window <= samples.count {
            var e: Float = 0
            for j in i ..< i + window { e += samples[j] * samples[j] }
            if e < bestEnergy { bestEnergy = e; best = i + window / 2 }
            i += window / 2
        }
        return best
    }
}

/// Polishes a dictation a few sentences at a time, in the background, as they're spoken — so at release only
/// the last sentences are left for the AI. Each block is polished once and reused.
@MainActor
public final class StreamingPolisher {
    public typealias Refine = @Sendable (String) async -> String?

    /// One sentence per block: each is polished while the next one is being said, so at release only the last
    /// sentence is left. (Measured: 3-sentence blocks left up to three sentences to do at release.)
    public static let sentencesPerBlock = 1
    /// Sentences this short ("Thanks.", "Sounds good.") have nothing for the AI to fix.
    public static let minWords = 5

    private var done: [String: String] = [:]
    private var running: [String: Task<String, Never>] = [:]
    private var queue: Task<Void, Never>?
    private let refine: Refine

    public private(set) var prefetched = 0

    public init(refine: @escaping Refine) {
        self.refine = refine
    }

    /// Start polishing the finished blocks of `text` — all but the block holding the last sentence, which
    /// may still change ("…, no, I mean …"). List lines are left as they are.
    public func prefetch(_ text: String, partialStart: Bool = false) {
        var blocks = Self.prose(text).flatMap(Self.blocks)
        if partialStart, !blocks.isEmpty { blocks.removeFirst() } // may be the tail of a cut sentence
        guard blocks.count > 1 else { return }
        for block in blocks.dropLast() where done[block] == nil && running[block] == nil
            && block.split(separator: " ").count >= Self.minWords
        {
            prefetched += 1
            start(block)
        }
    }

    /// The polished text: finished blocks from the cache, the rest now. Lines that are list items (or too
    /// short to need it) keep Evoo's own formatting.
    public func polish(_ text: String) async -> String {
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            guard Self.isProse(line) else { lines.append(line); continue }
            var out: [String] = []
            for block in Self.blocks(line) {
                if block.split(separator: " ").count < Self.minWords { out.append(block); continue }
                if let d = done[block] { out.append(d); continue }
                let task = running[block] ?? start(block)
                out.append(await task.value)
            }
            lines.append(out.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }

    static func isProse(_ line: String) -> Bool {
        line.range(of: #"^\s*(?:[-•*]|\d+\.|- \[ \]|☐)\s"#, options: .regularExpression) == nil
            && line.split(separator: " ").count >= 4
    }

    static func prose(_ text: String) -> [String] {
        text.components(separatedBy: "\n").filter(isProse)
    }

    /// How many of `text`'s blocks were already polished (for measuring).
    public func cachedBlocks(of text: String) -> (cached: Int, total: Int) {
        let blocks = Self.prose(text).flatMap(Self.blocks)
        return (blocks.filter { done[$0] != nil }.count, blocks.count)
    }

    @discardableResult
    private func start(_ block: String) -> Task<String, Never> {
        let previous = queue
        let refine = self.refine
        let task = Task { [weak self] () -> String in
            await previous?.value // one at a time, in order
            let polished = await refine(block) ?? block
            self?.done[block] = polished
            self?.running[block] = nil
            return polished
        }
        running[block] = task
        queue = Task { _ = await task.value }
        return task
    }

    /// Splits into blocks of whole sentences, counted from the start so earlier blocks stay identical as the
    /// dictation grows.
    static func blocks(_ text: String) -> [String] {
        let sentences = sentences(text)
        return stride(from: 0, to: sentences.count, by: sentencesPerBlock).map {
            sentences[$0 ..< min($0 + sentencesPerBlock, sentences.count)].joined(separator: " ")
        }
    }

    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            current.append(c)
            let next = i + 1 < chars.count ? chars[i + 1] : " "
            if ".?!".contains(c), next == " " || next == "\n" {
                // "e.g. " / "Dr. " / "3.5" aren't sentence ends: require the word before to be longer than 2 letters
                // or not a known abbreviation.
                let word = current.split(separator: " ").last.map(String.init) ?? ""
                if !["e.g.", "i.e.", "Dr.", "Mr.", "Mrs.", "Ms.", "vs.", "etc.", "a.m.", "p.m."].contains(word) {
                    out.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                }
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { out.append(rest) }
        return out
    }
}
