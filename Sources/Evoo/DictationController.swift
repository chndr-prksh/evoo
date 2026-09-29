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
    /// Opens the History & Notes window (owned by the app delegate).
    var onOpenHistory: (() -> Void)?
    /// Text selected when fn went down — the target of "rewrite by voice".
    private var selectionAtStart: String?

    private var smartCleanupReady: Bool {
        settings.smartCleanup && SystemInfo.canRunSmartCleanup && refiner.isLoaded
    }

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
    /// Generous: smart cleanup / rewrite-by-voice runs a local LLM (about a second on 16 GB Macs).
    private static let processingTimeoutSeconds: Double = 45

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
        settings.$smartCleanup.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.prepareRefiner() } }
            .store(in: &cancellables)
        settings.$refinerModel.combineLatest(settings.$refinementEnabled, settings.$language).dropFirst()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.prepareRefiner() }
            .store(in: &cancellables)
    }

    // MARK: - Startup

    func bootstrap() {
        DictationPipeline.preload()
        InstalledApps.shared.scan()
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
        let wanted = (settings.smartCleanup && SystemInfo.canRunSmartCleanup)
            || (Features.multilingual && settings.refinementEnabled)
        guard wanted else { return refiner.unload() }
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
                if SystemInfo.canRunSmartCleanup { settings.smartCleanup = true } // downloaded to use it
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
        selectionAtStart = smartCleanupReady ? ScreenText.selectedText() : nil
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
            if await runMacCommand(raw) { return }
            if runAppCommand(raw) { return }
            if try await rewriteSelectionIfAsked(raw, selection: selectionAtStart, session: session) { return }
            if try await composeIfAsked(raw, session: session) { return }
            // Smart cleanup (16 GB+): the local LLM polishes the dictation after the rules.
            // Otherwise the LLM only runs for Hinglish (multilingual builds).
            let policy: DictationPipeline.LLMPolicy = smartCleanupReady ? .polish
                : Features.multilingual && settings.refinementEnabled && refiner.isLoaded ? .whenNeeded : .off
            if policy != .off { phase = .refining }
            let names = await screenNames?.value ?? []
            let out = await pipeline.finish(raw: raw, asrMs: asrMs, language: language, style: style,
                                            contextTerms: names, tone: Tone.forApp(targetApp), llm: policy)
            learnFromScreen(seen: names, used: out.usedScreenTerms)
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
            offerTip()
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

    /// Controlling the Mac by voice (keys, Spotlight, Shortcuts, volume, windows, clicks, reminders, notes…).
    /// Returns true if the dictation was such a command.
    private func runMacCommand(_ raw: String) async -> Bool {
        guard settings.appCommands, let command = MacCommands.parse(TextCleaner.clean(raw)) else { return false }
        switch command {
        case let .spotlight(query):
            phase = .idle
            await MacActions.spotlight(query, injector: injector)
        case let .runShortcut(name):
            show(await MacActions.runShortcut(name) ?? "Ran “\(name)”")
        case let .keys(combo, name):
            if MacActions.press(combo) { show(name.prefix(1).uppercased() + name.dropFirst()) } else { show("Unknown key") }
        case let .volume(v): MacActions.setVolume(v); show("Volume \(v)%")
        case let .volumeStep(up): MacActions.stepVolume(up: up); show(up ? "Volume up" : "Volume down")
        case let .mute(on): MacActions.mute(on); show(on ? "Muted" : "Unmuted")
        case let .media(key): MacActions.media(key); show(key == .playPause ? "Play/Pause" : key == .next ? "Next" : "Previous")
        case let .darkMode(on): MacActions.darkMode(on); show(on ? "Dark mode" : "Light mode")
        case let .window(action):
            if !MacActions.window(action) { show("Couldn't move this window") } else { phase = .idle }
        case let .click(label):
            show(MacActions.click(label) ? "Clicked “\(label)”" : "Couldn't find “\(label)”")
        case let .reminder(task, due):
            show(await Assistant.addReminder(task, due: due))
        case let .event(title, start, minutes):
            show(await Assistant.addEvent(title, start: start, minutes: minutes))
        case let .note(text):
            DictationHistory.notes.add(text, app: targetApp)
            show("Noted")
        case let .askHistory(query):
            HistoryQuery.shared.text = query
            HistoryQuery.shared.showNotes = false
            phase = .idle
            onOpenHistory?()
        case .readAloud:
            if let text = ScreenText.selectedText() { Assistant.read(text); show("Reading aloud") }
            else { show("Select some text first") }
        case .stopReading:
            Assistant.stopReading()
            phase = .idle
        case .transcribeFile:
            phase = .idle
            transcribeFile()
        }
        return true
    }

    /// Screen words become permanent dictionary words when they fixed a dictation, or after they've shown up
    /// in several separate dictations (`ScreenLexicon.threshold`).
    private func learnFromScreen(seen: [String], used: [String]) {
        guard settings.learnFromScreen, !seen.isEmpty else { return }
        let promoted = settings.screenLexicon.observe(seen)
        let new = Array(Set(used + promoted)).filter { !settings.personalWords.contains($0) }.sorted()
        guard !new.isEmpty else { return }
        settings.personalWords += new
        settings.screenLearned += new
        if !used.isEmpty { show("Learned “\(used.joined(separator: "”, “"))” from your screen") }
    }

    /// Every few dictations, introduce one more feature (schedule in `Tips`).
    private func offerTip() {
        settings.dictationCount += 1
        guard settings.showTips else { return }
        var extra: [Tip] = []
        if SystemInfo.canRunSmartCleanup {
            extra.append(Tip(id: "rewrite", text: "With Smart cleanup on (Settings), select text and say:",
                             example: "make this more formal"))
        }
        guard let tip = Tips.next(afterUses: settings.dictationCount, shown: Set(settings.shownTips), extra: extra)
        else { return }
        settings.shownTips.append(tip.id)
        Task {
            try? await Task.sleep(for: .milliseconds(700)) // after the text has landed
            PillModel.shared.present(tip)
        }
    }

    func transcribeFile() {
        FileTranscriber.pickAndTranscribe { [weak self] status in self?.show(status) }
    }

    /// "open Slack", "search Google for …": do it instead of typing. Returns true if it was a command.
    private func runAppCommand(_ raw: String) -> Bool {
        guard settings.appCommands else { return false }
        let targets = InstalledApps.shared.targets(custom: settings.customApps)
        guard let command = AppCommands.parse(TextCleaner.clean(raw), targets: targets) else { return false }
        if let message = InstalledApps.shared.run(command) { show(message) } else { show("Couldn't open that") }
        return true
    }

    /// 16 GB Macs: "reply saying …" writes a reply to what's on screen; "translate to X, …" translates what
    /// you say. Returns true if it handled the dictation.
    private func composeIfAsked(_ raw: String, session: Int) async throws -> Bool {
        guard smartCleanupReady else { return false }
        let said = TextCleaner.clean(raw)
        var output: String?
        if let intent = ReplyPrompt.replyIntent(said) {
            phase = .refining
            let screen = await Task.detached { ScreenText.capture().joined(separator: "\n") }.value
            output = try await refiner.reply(screen: screen, intent: intent)
        } else if let (language, text) = ReplyPrompt.translation(said) {
            phase = .refining
            output = try await refiner.rewrite(text, instruction: "Translate to \(language)")
        } else {
            return false
        }
        guard !Task.isCancelled, session == self.session else { return true }
        guard let output else {
            show("Couldn't write that — try again")
            return true
        }
        await injector.insert(Self.spaced(output), restoreClipboard: settings.restoreClipboard)
        lastText = output
        phase = .idle
        return true
    }

    /// Rewrite by voice: text was selected and the dictation is an instruction ("make this formal").
    /// Returns true if it handled the dictation.
    private func rewriteSelectionIfAsked(_ raw: String, selection: String?, session: Int) async throws -> Bool {
        let instruction = TextCleaner.clean(raw)
        guard let selection, smartCleanupReady, RewritePrompt.isInstruction(instruction) else { return false }
        phase = .refining
        guard let rewritten = try await refiner.rewrite(selection, instruction: instruction),
              !Task.isCancelled, session == self.session
        else {
            show("Couldn't rewrite that — try again")
            return true
        }
        await injector.insert(rewritten, restoreClipboard: settings.restoreClipboard) // replaces the selection
        lastText = rewritten
        phase = .idle
        return true
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
            if await runMacCommand(text) { return }
            if runAppCommand(text) { return }
            let selection = smartCleanupReady ? ScreenText.selectedText() : nil
            if (try? await rewriteSelectionIfAsked(text, selection: selection, session: session)) == true { return }
            if (try? await composeIfAsked(text, session: session)) == true { return }
            // Same path as a real dictation after speech recognition: commands, edits, rules, formatting.
            let out = await pipeline.finish(raw: text, asrMs: 0, language: .english, style: OutputStyle.forApp(app),
                                            llm: smartCleanupReady ? .polish : .off)
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
