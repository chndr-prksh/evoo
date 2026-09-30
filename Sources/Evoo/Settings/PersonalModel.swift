import AppKit
import EvooCore
import EvooRefine
import Foundation
import IOKit.ps
import os

/// Layer 2: fine-tunes a small add-on (LoRA) for the polish model on this Mac, from the user's own edits, so
/// polish writes the way they do. Measured on a test persona: the plain 1.7B model wrote 0 of 28 held-back
/// messages the way the person sent them; with the add-on, 24 of 28.
///
/// Runs at night on power (or from Settings): prepares data, trains with MLX in a private Python environment,
/// converts the add-on for llama.cpp, and keeps it only if it's clearly closer to the user's held-back edits.
@MainActor
final class PersonalModel: ObservableObject {
    static let shared = PersonalModel()

    enum Status: Equatable {
        case idle
        case working(String)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    /// Summary of the add-on in use, e.g. "24 of 28 held-back messages exactly like you".
    @Published private(set) var result: String? = UserDefaults.standard.string(forKey: "personalModelResult")
    private let log = Logger(subsystem: "app.evoo", category: "personal-model")
    private var scheduler: NSBackgroundActivityScheduler?

    let dir = ModelPaths.root.deletingLastPathComponent().appendingPathComponent("personal", isDirectory: true)

    func adapter(for model: RefinerModel) -> URL { dir.appendingPathComponent("personal-\(model.rawValue).gguf") }
    func hasAdapter(for model: RefinerModel) -> Bool { FileManager.default.fileExists(atPath: adapter(for: model).path) }

    var editedPairs: Int { StyleStore.shared.pairs.filter { $0.edited && PersonalStyle.isUsable($0) }.count }
    var isBusy: Bool { if case .working = status { true } else { false } }

    /// The trainer needs Apple's Command Line Tools (for Python 3).
    var hasPython: Bool { FileManager.default.fileExists(atPath: "/Library/Developer/CommandLineTools/usr/bin/python3") }

    func remove(for model: RefinerModel) {
        try? FileManager.default.removeItem(at: adapter(for: model))
        result = nil
        UserDefaults.standard.removeObject(forKey: "personalModelResult")
    }

    // MARK: - Schedule

    /// Nightly: when on power, and there are enough new edits since the last training.
    func schedule(controller: DictationController) {
        let s = NSBackgroundActivityScheduler(identifier: "app.evoo.personal-training")
        s.repeats = true
        s.interval = 24 * 3600
        s.tolerance = 6 * 3600
        s.qualityOfService = .background
        s.schedule { [weak self] done in
            Task { @MainActor in
                guard let self else { return done(.finished) }
                let trainedOn = UserDefaults.standard.integer(forKey: "personalModelTrainedOn")
                if Self.onPower, controller.settings.learnStyle, self.hasPython,
                   self.editedPairs >= PersonalTraining.minPairs, self.editedPairs >= trainedOn + 100
                {
                    await self.train(controller: controller)
                }
                done(.finished)
            }
        }
        scheduler = s
    }

    static var onPower: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return true }
        return (type as String) == kIOPMACPowerKey
    }

    // MARK: - Training

    /// `pairs`/`iters` override the defaults (debug checks of the whole flow).
    func train(controller: DictationController, force: Bool = false, pairs override: [StylePair]? = nil,
               iters: Int = 120) async {
        guard !isBusy else { return }
        let model = controller.settings.refinerModel
        let pairs = override ?? StyleStore.shared.pairs
        guard force || override != nil || editedPairs >= PersonalTraining.minPairs else {
            status = .failed("Needs \(PersonalTraining.minPairs) edits — \(editedPairs) so far")
            return
        }
        guard hasPython else {
            status = .failed("Needs Apple's Command Line Tools (for Python): run  xcode-select --install")
            return
        }
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = dir.appendingPathComponent("data", isDirectory: true)
            try fm.createDirectory(at: data, withIntermediateDirectories: true)

            status = .working("Preparing your edits…")
            let split = PersonalTraining.split(pairs)
            for (name, rows) in [("train", split.train), ("valid", split.valid), ("test", split.test)] {
                try rows.map { PersonalTraining.record($0, model: model) }.joined(separator: "\n")
                    .write(to: data.appendingPathComponent("\(name).jsonl"), atomically: true, encoding: .utf8)
            }

            let python = try await trainerPython()

            // Training needs the memory the polish model is using (8 GB Macs ran out otherwise).
            status = .working("Training on \(split.train.count) of your edits… (about an hour; dictation still works)")
            controller.pauseRefinerForTraining()
            let candidate = dir.appendingPathComponent("candidate", isDirectory: true)
            try? fm.removeItem(at: candidate)
            let config = dir.appendingPathComponent("lora.yaml")
            try Self.config(model: PersonalTraining.mlxModel(for: model), data: data, adapter: candidate, iters: iters)
                .write(to: config, atomically: true, encoding: .utf8)
            try await run(python, [script("train_personal_lora.py"), "--config", config.path]) { line in
                if let r = line.range(of: #"(?<=Iter )\d+(?=:)"#, options: .regularExpression), let i = Double(line[r]) {
                    Task { @MainActor in self.status = .working("Training… \(Int(i * 100 / Double(iters)))%") }
                }
            }
            let gguf = dir.appendingPathComponent("candidate.gguf")
            try await run(python, [script("mlx_lora_to_gguf.py"), candidate.path, gguf.path])

            // The gate: better than the plain model on held-back edits, or it isn't used.
            status = .working("Testing it on edits it hasn't seen…")
            let verdict = try await controller.evaluateAdapter(gguf, on: split.test)
            if PersonalTraining.accept(baseDistance: verdict.base.distance, adapterDistance: verdict.adapter.distance,
                                       baseExact: verdict.base.exact, adapterExact: verdict.adapter.exact)
            {
                try? fm.removeItem(at: adapter(for: model))
                try fm.moveItem(at: gguf, to: adapter(for: model))
                let closer = Int(((1 - verdict.adapter.distance / max(verdict.base.distance, 0.0001)) * 100).rounded())
                result = "\(verdict.adapter.exact) of \(split.test.count) held-back messages exactly like you (plain model: \(verdict.base.exact)) · \(closer)% closer"
                UserDefaults.standard.set(result, forKey: "personalModelResult")
                UserDefaults.standard.set(editedPairs, forKey: "personalModelTrainedOn")
                log.notice("personal model accepted: \(self.result ?? "", privacy: .public)")
                status = .idle
            } else {
                status = .failed("Trained, but it wasn't better than the plain model yet — kept the current one")
                log.notice("personal model rejected: base \(verdict.base.distance) / \(verdict.base.exact), add-on \(verdict.adapter.distance) / \(verdict.adapter.exact)")
            }
            controller.prepareRefiner() // back to normal, with the add-on if there is one
        } catch {
            log.error("personal training failed: \(error.localizedDescription, privacy: .public)")
            status = .failed(error.localizedDescription)
            controller.prepareRefiner()
        }
    }

    static func config(model: String, data: URL, adapter: URL, iters: Int = 120) -> String {
        """
        model: \(model)
        train: true
        data: \(data.path)
        adapter_path: \(adapter.path)
        fine_tune_type: lora
        num_layers: 16
        batch_size: 1
        iters: \(iters)
        learning_rate: 0.0001
        steps_per_report: 10
        steps_per_eval: 1000
        val_batches: 6
        max_seq_length: 1400
        mask_prompt: true
        grad_checkpoint: true
        lora_parameters:
          rank: 8
          scale: 20.0
          dropout: 0.0
        """
    }

    private func script(_ name: String) -> String {
        Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "trainer")?.path
            ?? URL(fileURLWithPath: "scripts/\(name)").path
    }

    /// A private Python environment with MLX, created once (~300 MB).
    private func trainerPython() async throws -> String {
        let venv = dir.appendingPathComponent("venv")
        let python = venv.appendingPathComponent("bin/python").path
        if !FileManager.default.fileExists(atPath: python) {
            status = .working("Setting up the trainer (once, ~300 MB)…")
            try await run("/usr/bin/python3", ["-m", "venv", venv.path])
            try await run(python, ["-m", "pip", "install", "-q", "mlx-lm==0.29.1", "gguf", "numpy"])
        }
        return python
    }

    /// Runs a process off the main thread; throws with its last output if it fails.
    private func run(_ exe: String, _ args: [String], onLine: (@Sendable (String) -> Void)? = nil) async throws {
        try await Task.detached(priority: .background) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            try p.run()
            var tail = ""
            for try await line in pipe.fileHandleForReading.bytes.lines {
                onLine?(line)
                tail = String((tail + "\n" + line).suffix(600))
            }
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                throw NSError(domain: "Evoo", code: Int(p.terminationStatus),
                              userInfo: [NSLocalizedDescriptionKey: "Trainer failed: \(tail.suffix(200))"])
            }
        }.value
    }
}
