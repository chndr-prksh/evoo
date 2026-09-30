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
func runGolden(engine: SpeechEngine, pipeline: DictationPipeline, polish: Bool, json: String?) async throws {
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
            let out = await pipeline.finish(raw: raw, asrMs: asrMs, language: .english, style: .markdown,
                                            llm: polish ? .polish : .off)
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
func runStress(engine: SpeechEngine, pipeline: DictationPipeline, refiner: LlamaRefiner, polish: Bool,
               counts: [Int], modes: [String], json: String?) async throws
{
    let passages = try String(contentsOf: URL(fileURLWithPath: "Benchmarks/passages.txt"), encoding: .utf8)
        .split(separator: "\n").map(String.init)
    let clock = ContinuousClock()
    var results: [StressResult] = []
    for n in counts {
        let text = passages.prefix(n).joined(separator: " ")
        // A short natural pause between sentences, then 0.6 s of silence before fn is released.
        let spoken = passages.prefix(n).joined(separator: " [[slnc 250]] ")
        let clip = try speech(spoken) + [Float](repeating: 0, count: 9_600)
        let seconds = Double(clip.count) / 16_000
        for mode in modes {
            var recorded: [Float] = []
            let whole = SpeculativeTranscriber()
            let stream = StreamingDictation()
            let polisher = polish ? StreamingPolisher { t in try? await refiner.refine(t, language: .english) } : nil
            if mode == "stream", let polisher {
                stream.onCommit = { raw, partial in
                    let post = pipeline.postProcess(raw, language: .english, style: .markdown)
                    polisher.prefetch(post.text, partialStart: partial)
                }
            }
            var peak = residentMB()
            for start in stride(from: 0, to: clip.count, by: 1_600) {
                recorded += clip[start ..< min(start + 1_600, clip.count)]
                if mode == "stream" {
                    let from = stream.committedSamples
                    stream.consider(recent: Array(recorded[from...]), from: from, engine: engine)
                } else {
                    whole.consider(recorded, engine: engine)
                }
                try await Task.sleep(for: .milliseconds(100))
                if start % 16_000 == 0 { peak = max(peak, residentMB()) }
            }
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
