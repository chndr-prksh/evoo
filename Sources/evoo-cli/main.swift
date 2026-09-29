import EvooCore
import EvooRefine
import EvooSpeech
import FluidAudio
import Foundation

// Dev tool for measuring Evoo's pipeline without the GUI.
//
//   evoo-cli bench [--lang english] [--engine parakeet|whisper] [--llm] [--vocab "Divya,Rahul"] file.wav …   audio → text, with timings
//   evoo-cli post [--style markdown|plain|singleLine] "text" …                       rules + formatting only
//   evoo-cli refine [--lang …] [--model qwen3_1_7b|qwen3_4b] "text" …                 LLM refinement only
//
// Make test audio with macOS text-to-speech:
//   say -o /tmp/a.wav --data-format=LEI16@16000 "let's meet tomorrow, no, day after tomorrow"

var args = Array(CommandLine.arguments.dropFirst())
let command = args.isEmpty ? "" : args.removeFirst()

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i ... i + 1) }
    return args[i + 1]
}

func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

let language = option("--lang").flatMap(DictationLanguage.init(rawValue:)) ?? .english
let model = option("--model").flatMap(RefinerModel.init(rawValue:)) ?? .qwen3_1_7b
let engineID = option("--engine").flatMap(ASREngineID.init(rawValue:)) ?? EnginePreference.automatic.resolve(for: language)
let useLLM = flag("--llm")
let vocabulary = option("--vocab")?.split(separator: ",").map(String.init) ?? []
let style = option("--style").flatMap(OutputStyle.init(rawValue:)) ?? .markdown
let refiner = LlamaRefiner()
let pipeline = DictationPipeline(refiner: refiner)
pipeline.dictionary = PersonalDictionary(vocabulary)
let clock = ContinuousClock()

// Inputs from arguments, or one per line on stdin.
var inputs: [String] {
    if !args.isEmpty { return args }
    var lines: [String] = []
    while let line = readLine() {
        if !line.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(line) }
    }
    return lines
}

func loadRefiner() async throws {
    guard ModelDownloader.isInstalled(model) else {
        print("Model missing: \(ModelPaths.refiner(model).path) — download it from Evoo Settings first.")
        exit(1)
    }
    let t = try await clock.measure { try await refiner.load(model, language: language) }
    print("loaded \(model.rawValue) in \(t)\n")
}

switch command {
case "bench":
    let versions: [String: AsrModelVersion] = ["v2": .v2, "v3": .v3, "110m": .tdtCtc110m]
    let version = option("--parakeet").flatMap { versions[$0] } ?? .v3
    let engine: SpeechEngine = engineID == .parakeet ? ParakeetEngine(version: version) : WhisperEngine()
    let loadTime = try await clock.measure { try await engine.load { _ in } }
    await DictationPipeline.warmUp(engine)
    print("loaded \(engineID.rawValue) in \(loadTime)" + (vocabulary.isEmpty ? "" : ", vocabulary: \(vocabulary)"))
    if useLLM { try await loadRefiner() }
    let converter = AudioConverter()
    for path in inputs {
        let samples = try converter.resampleAudioFile(path: path)
        let out = try await pipeline.run(samples: samples, engine: engine, language: language,
                                         style: style, llm: useLLM ? .whenNeeded : .off)
        let audio = String(format: "%.1f", Double(samples.count) / 16000)
        print("\n\(URL(fileURLWithPath: path).lastPathComponent) (\(audio) s audio)")
        print("  raw: \(out.raw)\n  out: \(out.text)\n  \(out.summary)")
    }
    await engine.unload()

case "hold":
    // Replays each clip in real time as if fn were held, with a pause before release, and measures
    // fn-up → final text with speculative transcription (what the app does).
    let versions: [String: AsrModelVersion] = ["v2": .v2, "v3": .v3, "110m": .tdtCtc110m]
    let engine = ParakeetEngine(version: option("--parakeet").flatMap { versions[$0] } ?? .v3)
    try await engine.load { _ in }
    await DictationPipeline.warmUp(engine)
    let pause = Double(option("--pause") ?? "0.5") ?? 0.5
    let converter = AudioConverter()
    for path in inputs {
        let clip = try converter.resampleAudioFile(path: path) + [Float](repeating: 0, count: Int(pause * 16000))
        let speculator = await SpeculativeTranscriber()
        var recorded: [Float] = []
        for start in stride(from: 0, to: clip.count, by: 1600) { // 100 ms of audio per tick
            recorded += clip[start ..< min(start + 1600, clip.count)]
            await speculator.consider(recorded, engine: engine)
            try await Task.sleep(for: .milliseconds(100))
        }
        let released = clock.now
        let (raw, reused) = try await speculator.transcript(for: recorded, engine: engine)
        let out = await pipeline.finish(raw: raw, asrMs: 0, language: .english, style: style, llm: .off)
        let ms = (clock.now - released).formatted(.units(allowed: [.milliseconds]))
        print("\(URL(fileURLWithPath: path).lastPathComponent): fn up → text \(ms)\(reused ? "  (ready early)" : "")  \(out.text.prefix(60))")
    }

case "corpus":
    // Scores self-correction handling on a TSV of "input<TAB>expected" (Benchmarks/corrections.tsv).
    let quiet = flag("--quiet")
    let fallbackOnly = flag("--fallback") // LLM only when the rules left a correction word untouched
    let rewrite = flag("--rewrite") // local LLM polishes every sentence after the rules ("smart cleanup")
    let path = inputs.first ?? "Benchmarks/corrections.tsv"
    let cases = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
        .filter { !$0.hasPrefix("#") && $0.contains("\t") }
        .map { line -> (String, String) in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            return (parts[0], parts[1])
        }
    func loose(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == ":" } }
    var exact = 0, close = 0
    var worst = Duration.zero, total = Duration.zero
    if useLLM || rewrite { try await loadRefiner() }
    var llmRuns = 0, llmAccepted = 0
    for (input, expected) in cases {
        let t0 = clock.now
        var out = pipeline.postProcess(input, language: .english, style: nil).text
        let rulesActed = TextCleaner.clean(input).lowercased().filter(\.isLetter) != out.lowercased().filter(\.isLetter)
        if rewrite {
            llmRuns += 1
            let polished = try await refiner.refine(out, language: .english)
            if polished != out { llmAccepted += 1 }
            out = polished
        } else if useLLM, CorrectionPrompt.hasCue(input), !(fallbackOnly && rulesActed) {
            llmRuns += 1
            if let corrected = await pipeline.correctWithLLM(input, language: .english, style: nil) {
                out = corrected
                llmAccepted += 1
            }
        }
        let dt = clock.now - t0
        total += dt; worst = max(worst, dt)
        if out == expected { exact += 1 }
        if loose(out) == loose(expected) { close += 1 } else if !quiet {
            print("✘ \(input)\n    got:  \(out)\n    want: \(expected)")
        }
    }
    let n = cases.count
    let mode = rewrite ? "rules + \(model.rawValue) smart cleanup (changed \(llmAccepted) of \(llmRuns))" : useLLM ? "rules + \(model.rawValue)\(fallbackOnly ? " as fallback" : "") (ran on \(llmRuns), accepted \(llmAccepted))" : "rules"
    print("\n\(mode): \(close)/\(n) correct (\(exact) exact incl. punctuation) · avg \((total / n).formatted(.units(allowed: [.microseconds]))), worst \(worst.formatted(.units(allowed: [.milliseconds])))")

case "cloud-models":
    // Lists the models your key can use:  evoo-cli cloud-models --provider groq   (key in EVOO_CLOUD_KEY)
    guard let key = ProcessInfo.processInfo.environment["EVOO_CLOUD_KEY"], !key.isEmpty else {
        print("Set EVOO_CLOUD_KEY to your provider API key."); exit(2)
    }
    let provider = option("--provider").flatMap(CloudCorrector.Provider.init(rawValue:)) ?? .groq
    for id in try await CloudCorrector(provider: provider, apiKey: key).availableModels() { print(id) }

case "cloud":
    // Benchmarks hosted open-weight models on the correction scorecard: accuracy, latency, and how often
    // they'd beat a 300 ms budget. The API key comes from EVOO_CLOUD_KEY (never stored by the tool).
    //   EVOO_CLOUD_KEY=… evoo-cli cloud --provider groq [--model-name llama-3.1-8b-instant] Benchmarks/corrections.tsv
    guard let key = ProcessInfo.processInfo.environment["EVOO_CLOUD_KEY"], !key.isEmpty else {
        print("Set EVOO_CLOUD_KEY to your provider API key."); exit(2)
    }
    let provider = option("--provider").flatMap(CloudCorrector.Provider.init(rawValue:)) ?? .groq
    let cloud = CloudCorrector(provider: provider, apiKey: key, model: option("--model-name"))
    let budget = Double(option("--budget-ms") ?? "300") ?? 300
    let quietCloud = flag("--quiet")
    // Free tiers allow ~8,000 tokens/minute (~8 of these requests); pace to stay under it.
    let paceMs = Int(option("--pace-ms") ?? "0") ?? 0
    let path = inputs.first ?? "Benchmarks/corrections.tsv"
    let cases = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
        .filter { !$0.hasPrefix("#") && $0.contains("\t") }
        .map { $0.split(separator: "\t", maxSplits: 1).map(String.init) }
    func loose(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == ":" } }
    _ = try? await cloud.answer(for: "warm up") // open the connection first, like the app does on fn down
    var times: [Double] = []
    var cloudRight = 0, hybridRight = 0, rulesRight = 0, inBudget = 0, errors = 0, fallbackRight = 0
    for c in cases {
        let (input, expected) = (c[0], c[1])
        let rules = pipeline.postProcess(input, language: .english, style: nil).text
        if paceMs > 0 { try await Task.sleep(for: .milliseconds(paceMs)) }
        var answer = "error"
        var t0 = clock.now
        for attempt in 1 ... 6 {
            t0 = clock.now
            do {
                answer = try await cloud.answer(for: TextCleaner.clean(input))
                break
            } catch let CloudCorrector.CloudError.http(429, body) where attempt < 6 {
                // Free-tier rate limit: wait as long as the provider asks, then retry (not counted as latency).
                let wait = body.range(of: #"try again in ([0-9.]+)s"#, options: .regularExpression)
                    .flatMap { Double(body[$0].filter { $0.isNumber || $0 == "." }) } ?? 10
                print("  rate-limited, waiting \(Int(wait.rounded(.up))) s…")
                try await Task.sleep(for: .seconds(wait + 0.5))
            } catch {
                errors += 1
                if errors == 1 { print("request failed: \(error.localizedDescription)") }
                break
            }
        }
        let ms = Double((clock.now - t0).components.attoseconds) / 1e15 + Double((clock.now - t0).components.seconds) * 1000
        times.append(ms)
        let edited = CorrectionPrompt.parse(answer).flatMap { CorrectionPrompt.apply($0, to: TextCleaner.clean(input)) }
        // "none" keeps the rules' result; an error or an unusable answer counts as a miss for the cloud.
        let cloudOut = answer == "error" ? "" : edited.map { pipeline.postProcess($0, language: .english, style: nil).text } ?? rules
        // Hybrid = what the app would do: cloud answer if it arrives within budget, else the rules.
        let hybrid = ms <= budget && answer != "error" ? cloudOut : rules
        // Fallback: trust the rules whenever they changed something; ask the cloud only when a correction word
        // is present but the rules left the sentence as it was.
        let rulesActed = TextCleaner.clean(input).lowercased().filter(\.isLetter) != rules.lowercased().filter(\.isLetter)
        let fallback = !rulesActed && CorrectionPrompt.hasCue(input) && ms <= budget && answer != "error" ? cloudOut : rules
        if loose(fallback) == loose(expected) { fallbackRight += 1 }
        if ms <= budget { inBudget += 1 }
        if loose(cloudOut) == loose(expected) { cloudRight += 1 }
        if loose(hybrid) == loose(expected) { hybridRight += 1 }
        if loose(rules) == loose(expected) { rulesRight += 1 }
        if loose(cloudOut) != loose(expected), !quietCloud {
            print("✘ [\(Int(ms)) ms, answer \(answer)] \(input)\n    got:  \(cloudOut)\n    want: \(expected)")
        }
    }
    let sorted = times.sorted()
    let n = cases.count
    print("""

    \(provider.rawValue) · \(cloud.model)
      cloud alone:        \(cloudRight)/\(n) correct\(errors > 0 ? "  (\(errors) failed requests)" : "")
      rules alone:        \(rulesRight)/\(n) correct
      rules + cloud (≤\(Int(budget)) ms): \(hybridRight)/\(n) correct
      rules, cloud as backup:  \(fallbackRight)/\(n) correct
      latency: p50 \(Int(sorted[n / 2])) ms · p90 \(Int(sorted[n * 9 / 10])) ms · max \(Int(sorted.last!)) ms · within budget \(inBudget)/\(n)
    """)

case "post":
    for input in inputs {
        let t0 = clock.now
        let r = pipeline.postProcess(input, language: language, style: style)
        let us = (clock.now - t0).formatted(.units(allowed: [.microseconds]))
        print("in : \(input)\nout: \(r.text)\(r.unresolved ? "   [unresolved → LLM]" : "")  (\(us))\n")
    }

case "refine":
    try await loadRefiner()
    for input in inputs {
        var output = ""
        let t = try await clock.measure { output = try await refiner.refine(input, language: language) }
        print("in : \(input)\nout: \(output)\n    (\(t.formatted(.units(allowed: [.milliseconds]))))\n")
    }

default:
    print("usage: evoo-cli bench|post|refine [options] …  (see Sources/evoo-cli/main.swift)")
    exit(2)
}

refiner.unload() // free Metal buffers before exit
