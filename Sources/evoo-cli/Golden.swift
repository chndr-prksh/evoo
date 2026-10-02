import EvooCore
import EvooRefine
import EvooSpeech
import FluidAudio
import Foundation

// Golden set and stress tests (see Benchmarks/golden.tsv, Benchmarks/passages.txt).
//   evoo-cli golden [--parakeet 110m|v3] [--polish] [--json out.json]
//   evoo-cli stress [--parakeet 110m|v3] [--sentences 1,5,10,30,50] [--modes whole,stream] [--json out.json]

/// Speaks `text` with macOS text-to-speech into a cached 16 kHz WAV.
func speech(_ text: String, voice: String = "Samantha") throws -> [Float] {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("evoo-golden", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let name = String(UInt64(bitPattern: Int64(text.hashValue &+ voice.hashValue)), radix: 36)
    let file = dir.appendingPathComponent("\(stableHash(voice + text)).wav")
    _ = name
    if !FileManager.default.fileExists(atPath: file.path) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", voice, "-o", file.path, "--data-format=LEI16@16000", text]
        try p.run()
        p.waitUntilExit()
    }
    return try AudioConverter().resampleAudioFile(path: file.path)
}

func stableHash(_ s: String) -> String {
    var h: UInt64 = 1_469_598_103_934_665_603
    for b in s.utf8 { h = (h ^ UInt64(b)) &* 1_099_511_628_211 }
    return String(h, radix: 36)
}

func loose(_ s: String) -> String {
    s.lowercased().replacingOccurrences(of: #"[\s]+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".!?,")))
}

func words(_ s: String) -> [String] {
    s.lowercased().split { !($0.isLetter || $0.isNumber || $0 == "'") }.map(String.init)
}

/// Word error rate of `hyp` against `ref` (edit distance over words).
func wer(_ ref: String, _ hyp: String) -> Double {
    let r = words(ref), h = words(hyp)
    guard !r.isEmpty else { return h.isEmpty ? 0 : 1 }
    var d = Array(0 ... h.count)
    for i in 1 ... r.count {
        var prev = d[0]
        d[0] = i
        for j in stride(from: 1, through: h.count, by: 1) {
            let cur = d[j]
            d[j] = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] == h[j - 1] ? 0 : 1))
            prev = cur
        }
    }
    return Double(d[h.count]) / Double(r.count)
}

struct GoldenResult: Encodable {
    var category: String
    var said: String
    var check: String
    var expected: String
    var raw: String
    var output: String
    var pass: Bool
    var audioSeconds: Double
    var asrMs: Int
    var rulesMs: Int
    var polishMs: Int
}

@MainActor
func runGolden(engine: SpeechEngine, pipeline: DictationPipeline, refiner: LlamaRefiner, polish: Bool,
               contextual: Bool = false, json: String?) async throws {
    let url = URL(fileURLWithPath: "Benchmarks/golden.tsv")
    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    let targets = AppCommands.builtIn + [AppTarget(name: "Google Chrome", aliases: ["chrome"], bundleID: "com.google.Chrome"),
                                         AppTarget(name: "Slack", bundleID: "com.tinyspeck.slackmacgap")]
    var results: [GoldenResult] = []
    let clock = ContinuousClock()
    for line in lines where !line.hasPrefix("#") && !line.trimmingCharacters(in: .whitespaces).isEmpty {
        let f = line.components(separatedBy: "\t")
        guard f.count >= 3 else { continue }
        let (category, said, check) = (f[0], f[1], f[2])
        let expected = f.count > 3 ? f[3] : ""
        let samples = try speech(said)
        var t = clock.now
        let raw = try await engine.transcribe(samples, language: .english)
        let asrMs = (clock.now - t).ms
        var output = "", pass = false, rulesMs = 0, polishMs = 0
        switch check {
        case "mac", "nocommand":
            let c = MacCommands.parse(TextCleaner.clean(raw))
            let a = AppCommands.parse(raw, targets: targets)
            output = c.map { String(describing: $0) } ?? a.map { String(describing: $0) } ?? "(text)"
            pass = check == "nocommand" ? (c == nil && a == nil) : output.lowercased().hasPrefix(expected.lowercased())
        case "app":
            let a = AppCommands.parse(raw, targets: targets)
            output = a.map { String(describing: $0) } ?? "(none)"
            pass = output.hasPrefix(expected)
        case "edit":
            let e = VoiceEdit.parse(raw)
            output = e.map { String(describing: $0) } ?? "(none)"
            pass = output.hasPrefix(expected)
        default:
            t = clock.now
            // Contextual polish: like the app on 16 GB+ (every sentence, with the ones before it as context).
            let polisher = polish && contextual
                ? StreamingPolisher(contextual: true) { t, earlier in try? await refiner.refine(t, language: .english, context: earlier) }
                : nil
            let out = await pipeline.finish(raw: raw, asrMs: asrMs, language: .english, style: .markdown,
                                            llm: polish ? .polish : .off, polisher: polisher)
            rulesMs = out.postMs
            polishMs = out.refineMs
            _ = t
            output = out.text
            let pieces = expected.split(separator: "|").map { String($0) }
            switch check {
            case "text": pass = loose(output) == loose(expected)
            case "has": pass = pieces.allSatisfy { output.localizedCaseInsensitiveContains($0) || output.contains($0) }
            case "not": pass = !pieces.contains { output.contains($0) }
            default: pass = false
            }
        }
        let r = GoldenResult(category: category, said: said, check: check, expected: expected, raw: raw, output: output,
                             pass: pass, audioSeconds: Double(samples.count) / 16_000, asrMs: asrMs, rulesMs: rulesMs,
                             polishMs: polishMs)
        results.append(r)
        print("\(pass ? "✅" : "❌") [\(category)] \(said)\n    heard: \(raw)\n    got:   \(output.replacingOccurrences(of: "\n", with: " ⏎ "))  (asr \(asrMs) ms, rules \(rulesMs) ms\(polish ? ", polish \(polishMs) ms" : ""))")
    }
    let passed = results.filter(\.pass).count
    print("\nPASSED \(passed)/\(results.count)")
    for cat in Array(Set(results.map(\.category))).sorted() {
        let c = results.filter { $0.category == cat }
        print("  \(cat): \(c.filter(\.pass).count)/\(c.count)")
    }
    if let json {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(results).write(to: URL(fileURLWithPath: json))
    }
}

struct StressResult: Encodable {
    var mode: String
    var sentences: Int
    var words: Int
    var audioSeconds: Double
    var releaseToTextMs: Int
    var asrAtReleaseMs: Int
    var polishAtReleaseMs: Int
    var blocksReady: Int
    var blocksTotal: Int
    var wer: Double
    var output: String
    var peakMemoryMB: Double
}

func residentMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
}

/// Replays a dictation in real time as if fn were held (100 ms ticks, like the app), then measures fn-up → final
/// text. "whole": today's path (speculate the whole clip at pauses, polish everything at release).
/// "stream": commit stretches at pauses and polish finished sentences in the background.
@MainActor
func runStress(engine: SpeechEngine, pipeline: DictationPipeline, refiner: LlamaRefiner, polish: Bool, contextual: Bool = false,
               counts: [Int], modes: [String], json: String?, text custom: String? = nil) async throws
{
    // A custom text may carry its own pauses: "…the website [[slnc 500]] with the download link…".
    let passages = try custom.map { [$0] } ?? String(contentsOf: URL(fileURLWithPath: "Benchmarks/passages.txt"), encoding: .utf8)
        .split(separator: "\n").map(String.init)
    let counts = custom == nil ? counts : [1]
    let clock = ContinuousClock()
    var results: [StressResult] = []
    for n in counts {
        let text = passages.prefix(n).joined(separator: " ")
            .replacingOccurrences(of: #"\s*\[\[slnc \d+\]\]\s*"#, with: " ", options: .regularExpression)
        // A short natural pause between sentences, then 0.6 s of silence before fn is released.
        let spoken = passages.prefix(n).joined(separator: " [[slnc 250]] ")
        let clip = try speech(spoken) + [Float](repeating: 0, count: 9_600)
        let seconds = Double(clip.count) / 16_000
        for mode in modes {
            var recorded: [Float] = []
            let whole = SpeculativeTranscriber()
            let stream = StreamingDictation()
            let polisher = polish ? StreamingPolisher(contextual: contextual) { t, earlier in try? await refiner.refine(t, language: .english, context: earlier) } : nil
            // Exactly what the app does (DictationController.start): up to 45 s, pre-polish the whole-recording
            // transcript at each pause; beyond that, the committed pieces.
            var recordedCount = 0
            if mode == "stream", let polisher {
                stream.onWholeResult = { raw, atPause in
                    let post = pipeline.postProcess(raw, language: .english, style: .markdown)
                    if atPause { polisher.prefetchAll(post.text) } else { polisher.prefetch(post.text) }
                }
                stream.onCommit = { raw, partial in
                    guard recordedCount > Int(StreamingDictation.wholeClipLimit * 16_000) else { return }
                    let post = pipeline.postProcess(raw, language: .english, style: .markdown)
                    polisher.prefetch(post.text, partialStart: partial)
                }
            }
            var peak = residentMB()
            for start in stride(from: 0, to: clip.count, by: 1_600) {
                recorded += clip[start ..< min(start + 1_600, clip.count)]
                recordedCount = recorded.count
                if mode == "stream" {
                    let from = stream.committedSamples
                    stream.consider(recent: Array(recorded[from...]), from: from, engine: engine)
                    stream.considerWhole(recorded, engine: engine)
                } else {
                    whole.consider(recorded, engine: engine)
                }
                try await Task.sleep(for: .milliseconds(100))
                if start % 16_000 == 0 { peak = max(peak, residentMB()) }
            }
            stream.onWholeResult = nil
            stream.onCommit = nil
            let released = clock.now
            let raw: String
            if mode == "stream" { raw = try await stream.finish(recorded, engine: engine).text }
            else { raw = try await whole.transcript(for: recorded, engine: engine).text }
            let asrMs = (clock.now - released).ms
            let t = clock.now
            let ready = polisher.map { p in
                p.cachedBlocks(of: pipeline.postProcess(raw, language: .english, style: .markdown).text)
            } ?? (cached: 0, total: 0)
            let out = await pipeline.finish(raw: raw, asrMs: asrMs, language: .english, style: .markdown,
                                            llm: polish ? .polish : .off, polisher: mode == "stream" ? polisher : nil)
            let polishMs = (clock.now - t).ms
            let total = (clock.now - released).ms
            peak = max(peak, residentMB())
            let r = StressResult(mode: mode, sentences: n, words: words(text).count, audioSeconds: seconds,
                                 releaseToTextMs: total, asrAtReleaseMs: asrMs, polishAtReleaseMs: polishMs,
                                 blocksReady: ready.cached, blocksTotal: ready.total, wer: wer(text, out.text),
                                 output: out.text, peakMemoryMB: peak)
            results.append(r)
            if custom != nil {
                print("  → \(out.text)")
                let post = pipeline.postProcess(raw, language: .english, style: .markdown).text
                print("  raw: \(raw)\n  post: \(post)\n  sentences: \(StreamingPolisher.debugSentences(post).count) · prefetched \(polisher?.prefetched ?? 0) · skipped \(polisher?.skipped ?? 0)")
            }
            print(String(format: "%@ %2d sentences (%3d words, %5.1f s audio): fn-up → text %6d ms  [asr %5d, polish %6d, blocks ready %d/%d]  WER %.1f%%  mem %.0f MB",
                         mode.padding(toLength: 6, withPad: " ", startingAt: 0), n, r.words, seconds, total, asrMs, polishMs,
                         ready.cached, ready.total, r.wer * 100, peak))
            if let json {
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                try enc.encode(results).write(to: URL(fileURLWithPath: json))
            }
        }
    }
}

extension Duration {
    var ms: Int { Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000) }
}

// MARK: - Hinglish

/// Lenient key for Roman Hinglish words: "hai"/"he", "nahi"/"nahin", "accha"/"acha", "mein"/"me" match.
func hinglishKey(_ w: String) -> String {
    var s = w.lowercased().filter { $0.isLetter || $0.isNumber }
    for (a, b) in [("aa", "a"), ("ee", "i"), ("oo", "u"), ("chch", "ch"), ("cch", "ch"), ("chh", "ch"), ("ye", "e"), ("ya", "e"),
                   ("ah", "a"), ("w", "v"), ("z", "j"),
                   ("ph", "f"), ("ai", "e"), ("ei", "e"), ("th", "t"), ("dh", "d"), ("kh", "k"), ("gh", "g"),
                   ("bh", "b"), ("sh", "s")] {
        s = s.replacingOccurrences(of: a, with: b)
    }
    while s.count > 2, s.hasSuffix("n") || s.hasSuffix("h") { s.removeLast() } // nasal / aspirated endings
    return s
}

func hinglishWER(_ ref: String, _ hyp: String) -> Double {
    let norm = { (s: String) in
        s.lowercased().split { !($0.isLetter || $0.isNumber) }.map { hinglishKey(String($0)) }.joined(separator: " ")
    }
    return wer(norm(ref), norm(hyp))
}

@MainActor
func runHinglish(engine: SpeechEngine, pipeline: DictationPipeline, json: String?) async throws {
    let lines = try String(contentsOf: URL(fileURLWithPath: "Benchmarks/hinglish.tsv"), encoding: .utf8)
        .split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") && $0.contains("\t") }
    let clock = ContinuousClock()
    var total = 0.0, exactish = 0, ms: [Int] = []
    for line in lines {
        let f = line.components(separatedBy: "\t")
        let samples = try speech(f[0], voice: "Lekha")
        let t = clock.now
        let raw = try await engine.transcribe(samples, language: .hinglish)
        let asr = (clock.now - t).ms
        ms.append(asr)
        let out = pipeline.postProcess(raw, language: .hinglish, style: .plain).text
        let e = hinglishWER(f[1], out)
        total += e
        if e <= 0.1 { exactish += 1 }
        print(String(format: "%@ %4.0f%%  %@\n        want: %@\n        got:  %@  (%d ms)", e <= 0.1 ? "✅" : "  ", e * 100, f[0], f[1], out, asr))
    }
    let sorted = ms.sorted()
    print(String(format: "\nHINGLISH: %d/%d right (≤10%% word errors) · average word errors %.1f%% · speed median %d ms, max %d ms",
                 exactish, lines.count, total / Double(lines.count) * 100, sorted[sorted.count / 2], sorted.last ?? 0))
}
