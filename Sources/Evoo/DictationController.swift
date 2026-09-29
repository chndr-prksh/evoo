import AppKit
import Combine
import EvooCore
import EvooRefine
import EvooSpeech
import FluidAudio
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
    /// Result of the last learn-from-edits check, shown in Settings → Learning.
    @Published private(set) var learningStatus: String?

    let settings = AppSettings.shared
    let permissions = Permissions()

    private let log = Logger(subsystem: "app.evoo", category: "dictation")
    private let hotkeys = FnKeyMonitor()
    private let recorder = AudioRecorder()
    private let engines = SpeechEngines(parakeetVersion: AppSettings.shared.fastestModel ? .tdtCtc110m : .v3)
    private let refiner = LlamaRefiner()
    private lazy var pipeline = DictationPipeline(refiner: refiner)
    private let injector = TextInjector()
    private let editWatcher = EditWatcher()
    private let speculator = SpeculativeTranscriber()
    private var speculationLoop: Task<Void, Never>?
    /// Names read from the screen while the user speaks; ready by the time fn goes up.
    private var screenNames: Task<[String], Never>?
    private var targetApp: String?

    private var gesture: HotkeyGesture
    private var gestureTimer: Task<Void, Never>?
    private var processing: Task<Void, Never>?
    private var maxDurationTimer: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    /// Increments per dictation, so late results from an abandoned one are ignored.
    private var session = 0
    private var messageTimer: Task<Void, Never>?
    private var handsFreeFromUI = false
    private var cancellables: Set<AnyCancellable> = []

    private static let maxRecordingSeconds: Double = 300
    private static let minRecordingSeconds: Double = 0.3
    private static let processingTimeoutSeconds: Double = 20

    init() {
        gesture = HotkeyGesture(mode: AppSettings.shared.activationMode)
        hotkeys.onEvent = { [weak self] event in self?.handle(event) }
        editWatcher.onLessons = { [weak self] lessons, app in self?.learn(lessons, app: app) }
        editWatcher.onStatus = { [weak self] status in self?.learningStatus = status }
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
        settings.$fastestModel.dropFirst()
            .sink { [weak self] fastest in
                self?.engines.setParakeetVersion(fastest ? .tdtCtc110m : .v3)
                self?.prepareSpeechModel()
            }
            .store(in: &cancellables)
        settings.$snippets
            .sink { [weak self] snippets in self?.pipeline.snippets = snippets }
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

    /// Loads the model for the current language in the background. Never blocks dictation, and keeps
    /// the English model (Parakeet, small and fast) loaded so switching back is instant.
    func prepareSpeechModel() {
        let id = settings.resolvedEngine
        guard engines.ready(id) == nil else {
            modelStatus = nil
            engines.unload(except: [id, .parakeet])
            return
        }
        modelStatus = id == .whisper
            ? "Preparing the Hindi/Hinglish model — the first time takes a few minutes. English keeps working."
            : "Preparing the English model…"
        Task {
            do {
                try await engines.prepare(id)
                if settings.resolvedEngine == id { modelStatus = nil }
                engines.unload(except: [settings.resolvedEngine, .parakeet])
            } catch {
                modelStatus = "Speech model failed to load: \(error.localizedDescription)"
                log.error("ASR load failed: \(error.localizedDescription)")
            }
        }
    }

    func applyVocabulary() {
        pipeline.dictionary = PersonalDictionary(settings.personalWords)
    }

    func prepareRefiner() {
        guard Features.multilingual, settings.refinementEnabled else { return refiner.unload() }
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
        case .returnKey:
            return editWatcher.observe() // "send" — see what the user changed before it's gone
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
        editWatcher.observe()
        // Don't record if the model for this language isn't ready — say so instead of hanging.
        guard engines.ready(settings.resolvedEngine) != nil else {
            gesture.reset()
            prepareSpeechModel()
            let what = settings.resolvedEngine == .whisper ? "Hindi/Hinglish" : "English"
            return show("\(what) model is still preparing (first time only) — try again shortly")
        }
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
        // Read names on screen (chat header, recipients…) in the background while the user speaks.
        screenNames = settings.useScreenContext && permissions.granted[.accessibility] == true
            ? Task.detached(priority: .userInitiated) {
                ContextVocabulary.names(from: ScreenText.capture(), isKnownWord: DictationPipeline.isKnownWord)
            }
            : nil
        // While fn is held, transcribe during pauses so the text is ready the moment fn goes up.
        speculator.reset()
        speculationLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.phase == .recording,
                      let engine = self.engines.ready(self.settings.resolvedEngine) else { continue }
                self.speculator.consider(self.recorder.snapshot(), engine: engine)
            }
        }
        maxDurationTimer = Task {
            try? await Task.sleep(for: .seconds(Self.maxRecordingSeconds))
            if !Task.isCancelled, phase == .recording { stop() }
        }
    }

    func stop() {
        guard phase == .recording else { return }
        let releasedAt = ContinuousClock.now
        endRecordingSession()
        let samples = recorder.stop()
        let seconds = Double(samples.count) / AudioRecorder.sampleRate
        guard seconds >= Self.minRecordingSeconds, !AudioStats.isLikelySilent(samples) else {
            phase = .idle
            return
        }
        play("Pop")
        phase = .transcribing
        // Style the text for the app that will receive it: Markdown, bullets, or a single line for terminals.
        let targetApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        self.targetApp = targetApp
        let style: OutputStyle? = settings.formatText ? OutputStyle.forApp(targetApp) : nil
        session += 1
        let current = session
        processing = Task {
            await process(samples, seconds: seconds, style: style, session: current, releasedAt: releasedAt)
        }
        // Safety net: never stay stuck in "transcribing".
        watchdog?.cancel()
        watchdog = Task {
            try? await Task.sleep(for: .seconds(Self.processingTimeoutSeconds))
            guard !Task.isCancelled, session == current, phase == .transcribing || phase == .refining else { return }
            processing?.cancel()
            show("That took too long — please try again")
        }
    }

    func cancel() {
        endRecordingSession()
        _ = recorder.stop()
        processing?.cancel()
        watchdog?.cancel()
        session += 1
        phase = .idle
    }

    private func endRecordingSession() {
        maxDurationTimer?.cancel()
        speculationLoop?.cancel()
        gesture.reset()
        handsFreeFromUI = false
    }

    private func process(_ samples: [Float], seconds: Double, style: OutputStyle?, session: Int,
                         releasedAt: ContinuousClock.Instant) async
    {
        let language = settings.language
        guard let engine = engines.ready(settings.resolvedEngine) else {
            return show("Speech model isn't ready yet — try again shortly")
        }
        do {
            let asrStart = ContinuousClock.now
            let (raw, reused) = try await speculator.transcript(for: samples, engine: engine)
            let asrMs = (ContinuousClock.now - asrStart).ms
            // The LLM only runs for corrections the rules can't resolve, and for Hinglish (multilingual builds).
            let willUseLLM = Features.multilingual && settings.refinementEnabled && refiner.isLoaded
            if willUseLLM, language != .english { phase = .refining }
            let names = await screenNames?.value ?? []
            let out = await pipeline.finish(raw: raw, asrMs: asrMs, language: language, style: style,
                                            contextTerms: names, llm: willUseLLM ? .whenNeeded : .off)
            // Cancelled, timed out, or superseded by a newer dictation: don't paste stale text.
            guard !Task.isCancelled, session == self.session else { return }
            if out.action == .undo {
                injector.undo()
                return (phase = .idle)
            }
            if case let .edit(edit) = out.action {
                await applyVoiceEdit(edit, style: style ?? .plain)
                return (phase = .idle)
            }
            guard !out.text.isEmpty else { return (phase = .idle) }

            // Habits learned from the user's edits in this app (e.g. no final full stop in WhatsApp).
            let text = settings.learnFromEdits
                ? settings.habits.adapt(out.text, app: targetApp) { [personal = settings.personalWords] word in
                    personal.contains(word) || !DictationPipeline.isKnownWord(word.lowercased())
                }
                : out.text
            let spaced = Self.spaced(text)
            await injector.insert(spaced, restoreClipboard: settings.restoreClipboard)
            if settings.learnFromEdits, out.action != .pressEnter { editWatcher.didInsert(text, app: targetApp) }
            if out.action == .pressEnter { await injector.pressReturn() }
            lastText = text
            if settings.keepHistory { DictationHistory.shared.add(text, app: targetApp) }
            let totalMs = (ContinuousClock.now - releasedAt).ms
            lastTimings = String(format: "%.1fs audio · ", seconds) + out.summary
                + " · fn up → pasted \(totalMs) ms" + (reused ? " (ready early)" : "")
            log.info("\(self.lastTimings ?? "", privacy: .public)")
            phase = .idle
        } catch {
            guard session == self.session else { return }
            show(error.localizedDescription)
        }
        watchdog?.cancel()
    }

    /// Applies what the user's edits taught us: new names go into the personal dictionary,
    /// habits are counted per app.
    private func learn(_ lessons: [EditLearner.Lesson], app: String) {
        guard settings.learnFromEdits else { return }
        var learned: [String] = []
        for case let .word(heard, meant) in lessons {
            // Only names and unusual words — not ordinary typo fixes like "there" → "their".
            let isName = meant.first?.isUppercase == true || !DictationPipeline.isKnownWord(meant.lowercased())
            guard isName, meant.count >= 2, heard != meant, !settings.personalWords.contains(meant) else { continue }
            settings.personalWords.append(meant)
            learned.append(meant)
        }
        settings.habits.record(lessons, app: app)
        if !learned.isEmpty, phase == .idle || isMessage {
            show("Learned “\(learned.joined(separator: "”, “"))”")
        }
    }

    /// Adds a space when dictating right after existing text ("…5 PM." + "We need…"), like typing would.
    static func spaced(_ text: String) -> String {
        guard let before = ScreenText.characterBeforeCursor(), !before.isWhitespace,
              let first = text.first, !",.;:!?)".contains(first), !text.hasPrefix("\n") else { return text }
        return " " + text
    }

    /// "replace Tuesday with Wednesday" etc.: rewrites the text Evoo last typed, in place.
    private func applyVoiceEdit(_ edit: VoiceEdit, style: OutputStyle) async {
        guard let last = lastText, let edited = edit.apply(to: last, style: style) else {
            return show(lastText == nil ? "Nothing to edit yet" : "Couldn't find that in your last dictation")
        }
        // Select exactly what Evoo typed, so pasting replaces only that; otherwise undo it and retype.
        var selected = false
        if let field = ScreenText.focusedField(), let value = ScreenText.value(of: field),
           let range = value.range(of: last, options: .backwards)
        {
            selected = ScreenText.select(NSRange(range, in: value), in: field)
        }
        if !selected {
            injector.undo()
            try? await Task.sleep(for: .milliseconds(80))
        }
        if edited.isEmpty {
            if selected { injector.deleteSelection() }
        } else {
            await injector.insert(edited, restoreClipboard: settings.restoreClipboard)
        }
        lastText = edited.isEmpty ? nil : edited
    }

    func repasteLast() {
        guard let lastText else { return }
        Task { await injector.insert(lastText, restoreClipboard: settings.restoreClipboard) }
    }

    #if DEBUG
    /// Debug builds: type `text` as if it had been dictated (for end-to-end tests of pasting and learning).
    /// Trigger: post the distributed notification "app.evoo.debug.dictate" with the text as its object.
    func debugDictate(_ text: String) {
        Task {
            let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            // Same path as a real dictation after speech recognition: commands, edits, rules, formatting.
            let out = await pipeline.finish(raw: text, asrMs: 0, language: .english, style: OutputStyle.forApp(app),
                                            llm: .off)
            if case let .edit(edit) = out.action { return await applyVoiceEdit(edit, style: OutputStyle.forApp(app)) }
            await injector.insert(Self.spaced(out.text), restoreClipboard: settings.restoreClipboard)
            lastText = out.text
            editWatcher.didInsert(out.text, app: app)
        }
    }

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

private extension Duration {
    var ms: Int { Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000) }
}
