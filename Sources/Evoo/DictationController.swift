import AppKit
import Combine
import EvooCore
import EvooRefine
import EvooSpeech
import os

/// Owns the dictation lifecycle:
/// Fn → record → local ASR → clean → local LLM refine → paste at cursor.
@MainActor
final class DictationController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case refining
        case message(String) // transient notice shown in the pill
    }

    @Published private(set) var phase: Phase = .idle
    /// Recent input levels (0…1) for the pill waveform, newest last.
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: 18)
    @Published private(set) var lastText: String?
    @Published private(set) var lastTimings: String?
    /// Human-readable model status, e.g. "Downloading Whisper… 42%".
    @Published private(set) var modelStatus: String?
    @Published private(set) var refinerDownloadProgress: Double?

    let settings = AppSettings.shared
    let permissions = Permissions()

    private let log = Logger(subsystem: "app.evoo", category: "dictation")
    private let hotkeys = FnKeyMonitor()
    private let recorder = AudioRecorder()
    private let engines = SpeechEngines()
    private let refiner = LlamaRefiner()
    private lazy var pipeline = DictationPipeline(refiner: refiner)
    private let injector = TextInjector()

    private var gesture: HotkeyGesture
    private var gestureTimer: Task<Void, Never>?
    private var processing: Task<Void, Never>?
    private var maxDurationTimer: Task<Void, Never>?
    private var messageTimer: Task<Void, Never>?
    private var handsFreeFromUI = false
    private var cancellables: Set<AnyCancellable> = []

    private static let maxRecordingSeconds: Double = 300
    private static let minRecordingSeconds: Double = 0.3

    init() {
        gesture = HotkeyGesture(mode: AppSettings.shared.activationMode)
        hotkeys.onEvent = { [weak self] event in self?.handle(event) }
        recorder.onLevel = { [weak self] level in
            Task { @MainActor in self?.push(level: level) }
        }

        settings.$activationMode.dropFirst().sink { [weak self] mode in
            self?.gesture = HotkeyGesture(mode: mode)
        }.store(in: &cancellables)
        settings.$language.combineLatest(settings.$engine).dropFirst()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.prepareSpeechModel() }
            .store(in: &cancellables)
        settings.$personalWords.dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.applyVocabulary() }
            .store(in: &cancellables)
        settings.$refinerModel.combineLatest(settings.$refinementEnabled, settings.$language).dropFirst()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.prepareRefiner() }
            .store(in: &cancellables)
    }

    // MARK: - Startup

    func bootstrap() {
        DictationPipeline.preload()
        applyVocabulary()
        permissions.refresh()
        startHotkeysIfPossible()
        prepareSpeechModel()
        prepareRefiner()
    }

    func startHotkeysIfPossible() {
        permissions.refresh()
        if !hotkeys.isRunning, permissions.granted[.inputMonitoring] == true {
            hotkeys.start()
        }
    }

    func prepareSpeechModel() {
        let engine = engines.engine(for: settings.resolvedEngine)
        guard !engine.isLoaded else { return }
        let name = engine.id == .parakeet ? "Parakeet" : "Whisper"
        modelStatus = "Loading \(name)… (first run downloads it)"
        Task {
            do {
                try await engine.load { _ in }
                await DictationPipeline.warmUp(engine) // first dictation shouldn't pay CoreML warm-up
                modelStatus = nil
            } catch {
                modelStatus = "\(name) failed: \(error.localizedDescription)"
                log.error("ASR load failed: \(error.localizedDescription)")
            }
        }
    }

    func applyVocabulary() {
        pipeline.dictionary = PersonalDictionary(settings.personalWords)
    }

    func prepareRefiner() {
        guard settings.refinementEnabled else { return refiner.unload() }
        let model = settings.refinerModel
        guard ModelDownloader.isInstalled(model) else { return }
        Task {
            do { try await refiner.load(model, language: settings.language) } catch {
                log.error("Refiner load failed: \(error.localizedDescription)")
            }
        }
    }

    func downloadRefiner() {
        let model = settings.refinerModel
        guard refinerDownloadProgress == nil else { return }
        refinerDownloadProgress = 0
        Task {
            do {
                try await ModelDownloader.download(model) { p in
                    Task { @MainActor in self.refinerDownloadProgress = p }
                }
                refinerDownloadProgress = nil
                prepareRefiner()
            } catch {
                refinerDownloadProgress = nil
                show("Download failed: \(error.localizedDescription)")
            }
        }
    }

    var refinerInstalled: Bool { ModelDownloader.isInstalled(settings.refinerModel) }

    // MARK: - Hotkey

    private func handle(_ event: FnKeyMonitor.Event) {
        let now = ProcessInfo.processInfo.systemUptime
        switch event {
        case .escape:
            if phase == .recording { cancel() }
            return
        case .fnDown where handsFreeFromUI && phase == .recording:
            return stop()
        case .fnDown: apply(gesture.handle(.fnDown(at: now)))
        case .fnUp: apply(gesture.handle(.fnUp(at: now)))
        case .otherKey: apply(gesture.handle(.otherKey(at: now)))
        }
        scheduleGestureTimeout()
    }

    private func scheduleGestureTimeout() {
        gestureTimer?.cancel()
        guard let deadline = gesture.pendingDeadline else { return }
        let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime) + 0.01
        gestureTimer = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            apply(gesture.timeout(now: ProcessInfo.processInfo.systemUptime))
        }
    }

    private func apply(_ action: HotkeyAction?) {
        switch action {
        case .start: start()
        case .stop: stop()
        case .cancel: cancel()
        case nil: break
        }
    }

    // MARK: - Lifecycle

    /// Hands-free start/stop from the pill's mic button or the menu.
    func toggleFromUI() {
        if phase == .recording {
            stop()
        } else {
            gesture.reset()
            start()
            handsFreeFromUI = phase == .recording
        }
    }

    func start() {
        guard phase == .idle || isMessage else { return }
        permissions.refresh()
        guard permissions.granted[.microphone] == true else {
            permissions.request(.microphone)
            return show("Allow microphone access for Evoo")
        }
        do {
            try recorder.start(deviceUID: settings.microphoneUID)
        } catch {
            gesture.reset()
            return show(error.localizedDescription)
        }
        phase = .recording
        levels = levels.map { _ in 0 }
        play("Tink")
        maxDurationTimer = Task {
            try? await Task.sleep(for: .seconds(Self.maxRecordingSeconds))
            if !Task.isCancelled, phase == .recording { stop() }
        }
    }

    func stop() {
        guard phase == .recording else { return }
        endRecordingSession()
        let samples = recorder.stop()
        let seconds = Double(samples.count) / AudioRecorder.sampleRate
        guard seconds >= Self.minRecordingSeconds, !AudioStats.isLikelySilent(samples) else {
            phase = .idle
            return
        }
        play("Pop")
        phase = .transcribing
        processing = Task { await process(samples, seconds: seconds) }
    }

    func cancel() {
        endRecordingSession()
        _ = recorder.stop()
        processing?.cancel()
        phase = .idle
    }

    private func endRecordingSession() {
        maxDurationTimer?.cancel()
        gesture.reset()
        handsFreeFromUI = false
    }

    private func process(_ samples: [Float], seconds: Double) async {
        let language = settings.language
        let engine = engines.engine(for: settings.resolvedEngine)
        do {
            if !engine.isLoaded {
                modelStatus = "Loading speech model…"
                try await engine.load { _ in }
                modelStatus = nil
            }
            // The LLM only runs for corrections the rules can't resolve, and for Hinglish/Hindi.
            let willUseLLM = settings.refinementEnabled && refiner.isLoaded
            if willUseLLM, language != .english { phase = .refining }
            let out = try await pipeline.run(samples: samples, engine: engine, language: language,
                                             llm: willUseLLM ? .whenNeeded : .off)
            guard !Task.isCancelled else { return }
            guard !out.text.isEmpty else { return (phase = .idle) }

            await injector.insert(out.text, restoreClipboard: settings.restoreClipboard)
            lastText = out.text
            lastTimings = String(format: "%.1fs audio · ", seconds) + out.summary
            log.info("\(self.lastTimings ?? "", privacy: .public)")
            phase = .idle
        } catch {
            show(error.localizedDescription)
        }
    }

    func repasteLast() {
        guard let lastText else { return }
        Task { await injector.insert(lastText, restoreClipboard: settings.restoreClipboard) }
    }

    #if DEBUG
    /// Lets `--snapshot-pill` render every state without a microphone.
    func debugSet(phase: Phase, levels: [Float]? = nil) {
        self.phase = phase
        if let levels { self.levels = levels }
    }
    #endif

    // MARK: - Helpers

    private var isMessage: Bool {
        if case .message = phase { true } else { false }
    }

    private func show(_ message: String) {
        phase = .message(message)
        messageTimer?.cancel()
        messageTimer = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled, isMessage { phase = .idle }
        }
    }

    private func push(level: Float) {
        guard phase == .recording else { return }
        levels.removeFirst()
        levels.append(level)
    }

    private func play(_ name: String) {
        guard settings.playSounds else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
