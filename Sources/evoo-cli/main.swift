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
