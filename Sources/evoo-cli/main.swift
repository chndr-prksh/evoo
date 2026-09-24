import EvooCore
import EvooRefine
import Foundation

// Usage:
//   swift run -c release evoo-cli refine [--lang english|hinglish|hindi] [--model qwen3_1_7b|qwen3_4b] "text" ...
//   swift run -c release evoo-cli refine --lang english < samples.txt      (one transcript per line)

var args = Array(CommandLine.arguments.dropFirst())
guard args.first == "refine" else {
    print("usage: evoo-cli refine [--lang english|hinglish|hindi] [--model qwen3_1_7b|qwen3_4b] [text…]")
    exit(2)
}
args.removeFirst()

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i ... i + 1) }
    return args[i + 1]
}

let language = option("--lang").flatMap(DictationLanguage.init(rawValue:)) ?? .english
let model = option("--model").flatMap(RefinerModel.init(rawValue:)) ?? .qwen3_1_7b
var inputs = args
if inputs.isEmpty {
    while let line = readLine() {
        if !line.trimmingCharacters(in: .whitespaces).isEmpty { inputs.append(line) }
    }
}

guard ModelDownloader.isInstalled(model) else {
    print("Model missing: \(ModelPaths.refiner(model).path)\nDownload it from Evoo Settings first.")
    exit(1)
}

let refiner = LlamaRefiner()
let clock = ContinuousClock()
let loadTime = try await clock.measure { try await refiner.load(model, language: language) }
print("loaded \(model.rawValue) in \(loadTime)\n")

for input in inputs {
    var output = ""
    let t = try await clock.measure { output = try await refiner.refine(input, language: language) }
    print("in : \(input)\nout: \(output)\n    (\(t.formatted(.units(allowed: [.milliseconds]))))\n")
}

refiner.unload() // free Metal buffers before exit
