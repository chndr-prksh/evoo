import EvooCore
import EvooSpeech
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissions: Permissions
    @State private var launchAtLogin = LoginItem.isEnabled
    @ObservedObject private var style = StyleStore.shared
    @ObservedObject private var personal = PersonalModel.shared
    @State private var pillPlace = Self.currentPillPlace
    @State private var hinglishInstalled = HinglishAddon.isInstalled
    @State private var hinglishProgress: Double?
    @State private var hinglishError: String?

    static let pillPlaces: [(name: String, x: Double, y: Double)] = [
        ("Bottom left", 0.12, 0), ("Bottom center", 0.5, 0), ("Bottom right", 0.88, 0),
        ("Left side", 0.0, 0.5), ("Right side", 1.0, 0.5),
    ]

    static var currentPillPlace: String {
        let x = PillModel.shared.position, y = PillModel.shared.positionY
        return pillPlaces.first { abs($0.x - x) < 0.02 && abs($0.y - y) < 0.02 }?.name ?? "Custom (dragged)"
    }
    // Filled in on appear: listing devices talks to CoreAudio, too slow for init (which runs on every redraw).
    @State private var microphones: [AudioDevices.Device] = []
    @State private var loginError: String?
    @State private var newWord = ""

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            AppsSettingsView(settings: settings, installed: .shared)
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
        }
        .frame(width: 520, height: 680)
    }

    private var general: some View {
        Form {
            Section("Permissions") {
                ForEach(Permissions.Kind.allCases) { kind in
                    HStack {
                        Image(systemName: permissions.granted[kind] == true ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(permissions.granted[kind] == true ? .green : .orange)
                        VStack(alignment: .leading) {
                            Text(kind.title)
                            Text(kind.reason).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if permissions.granted[kind] != true {
                            Button("Grant…") { permissions.request(kind) }
                        }
                    }
                }
                Text("Set System Settings › Keyboard › “Press 🌐 key to” → Do Nothing, so macOS doesn't also react to Fn.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Dictation") {
                Picker("Fn key", selection: $settings.activationMode) {
                    ForEach(ActivationMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Language", selection: $settings.language) {
                    ForEach(Features.languages, id: \.self) { Text($0.title).tag($0) }
                }
                if DictationLanguage.european.contains(settings.language) {
                    Text("\(settings.language.englishName) (beta): Evoo writes what the speech model hears. Self-corrections, number formatting, lists, voice commands and AI polish are English-only for now. Languages you pick here also appear in the pill's 🌐 menu.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Fastest speech model", isOn: $settings.fastestModel)
                    .disabled(settings.language != .english)
                Text(settings.language != .english ? "Other languages always use the accurate model (Parakeet 0.6B)."
                    : settings.fastestModel
                    ? "Parakeet 110M: about 2× faster, but less accurate with names and casing."
                    : "Parakeet 0.6B: most accurate. Text is usually ready the instant you release fn.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Format lists, line breaks and emails", isOn: $settings.formatText)
                if settings.formatText {
                    Text("Say “…buy bread, eggs, milk” for bullets, “first… second… third…” for steps, “new line” / “new paragraph” for breaks. Styled per app: Markdown in Notion, editors and browsers; • bullets in Mail, Notes and Slack; always one line in Terminal.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Keep the microphone ready", isOn: $settings.keepMicReady)
                Text("Dictation starts the instant you press fn, including the moment just before it — so your first word is never cut. The mic stays on between dictations (macOS shows its orange dot); only the last 0.3 seconds are kept in memory, and nothing is transcribed or saved until you press fn.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Microphone", selection: $settings.microphoneUID) {
                    Text("System default").tag(String?.none)
                    ForEach(microphones) { Text($0.name).tag(Optional($0.id)) }
                }
            }

            Section("Personal dictionary") {
                Menu("Add a vocabulary pack") {
                    ForEach(VocabularyPacks.packs, id: \.name) { pack in
                        Button("\(pack.name) (\(pack.terms.count) terms)") {
                            settings.personalWords += pack.terms.filter { !settings.personalWords.contains($0) }
                        }
                    }
                }
                Toggle("Recognize names on screen", isOn: $settings.useScreenContext)
                Toggle("Learn unusual words from my screen", isOn: $settings.learnFromScreen)
                    .disabled(!settings.useScreenContext)
                if !settings.screenLearned.isEmpty {
                    Text("Learned from your screen: " + settings.screenLearned.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Forget words learned from the screen") {
                        settings.personalWords.removeAll { settings.screenLearned.contains($0) }
                        settings.screenLearned = []
                        settings.screenLexicon = ScreenLexicon()
                    }
                }
                Text("While you dictate, Evoo reads names visible in the current window — a chat's contact, email recipients, the text you're replying to — so it spells them right. Read locally for that dictation only; never stored. Password fields are skipped.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Names and terms Evoo should always spell right, e.g. Divya, Aarav, Kubernetes. Misheard words that sound like them are corrected; real English words are never changed.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Add a word or name", text: $newWord)
                        .onSubmit(addWord)
                    Button("Add", action: addWord)
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(settings.personalWords, id: \.self) { word in
                    HStack {
                        Text(word)
                        Spacer()
                        Button {
                            settings.personalWords.removeAll { $0 == word }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove")
                    }
                }
            }

            Section("Hinglish (add-on, beta)") {
                Text("Dictate in Hinglish — Hindi and English mixed, written the way people type it in chat (\"kal meeting hai, please confirm kar dena\"). Uses its own speech model, so English stays exactly as it is. Switch languages from the pill or here. Runs on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                if hinglishInstalled {
                    Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Remove Hinglish add-on", role: .destructive) {
                        settings.language = .english
                        HinglishAddon.remove()
                        hinglishInstalled = false
                    }
                } else if let p = hinglishProgress {
                    ProgressView(value: p) { Text("Downloading… \(Int(p * 100))%") }
                } else {
                    HStack {
                        Text("\(HinglishAddon.sizeMB) MB, once").foregroundStyle(.secondary)
                        Spacer()
                        Button("Download") {
                            hinglishError = nil
                            hinglishProgress = 0
                            Task {
                                do {
                                    try await HinglishAddon.download { p in Task { @MainActor in hinglishProgress = p } }
                                    hinglishInstalled = true
                                } catch { hinglishError = error.localizedDescription }
                                hinglishProgress = nil
                            }
                        }
                    }
                }
                if let hinglishError { Text(hinglishError).font(.caption).foregroundStyle(.red) }
            }

            if false { // old Whisper + LLM path, kept for reference
                Section("Speech model") {
                    Picker("Engine", selection: $settings.engine) {
                        ForEach(EnginePreference.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    LabeledContent("In use", value: settings.resolvedEngine.title)
                    if let status = controller.modelStatus {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Local AI (optional)") {
                    Text("Corrections, fillers and numbers are handled instantly by built-in rules. The local AI only runs for Hinglish/Hindi and for corrections the rules can't resolve, and adds about 1 s when it does.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Use local AI when needed", isOn: $settings.refinementEnabled)
                    Picker("Model", selection: $settings.refinerModel) {
                        ForEach(RefinerModel.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .disabled(!settings.refinementEnabled)
                    if let progress = controller.refinerDownloadProgress {
                        ProgressView(value: progress) { Text("Downloading \(Int(progress * 100))%") }
                    } else if !controller.refinerInstalled {
                        HStack {
                            Text("Not downloaded yet").foregroundStyle(.secondary)
                            Spacer()
                            Button("Download") { controller.downloadRefiner() }
                        }
                    } else {
                        Label("Installed", systemImage: "checkmark").foregroundStyle(.secondary)
                    }
                }

            } else if let status = controller.modelStatus {
                Section("Speech model") {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Smart cleanup (local AI)") {
                if SystemInfo.canRunSmartCleanup {
                    Toggle("Polish every dictation with local AI", isOn: $settings.smartCleanup)
                        .disabled(!controller.refinerInstalled)
                    Text("A local model tidies what you said — corrections, grammar, messy phrasing, misheard words (“went up the hell” → “hill”) — after Evoo's rules." + (SystemInfo.isLowMemory ? "" : " With the 1.7B or 4B model it also reads what you said just before, and the text already in the box, to understand the topic.") + " Also enables rewrite by voice: select text, hold fn, say “make this more formal”, “shorten this”, “translate to Hindi”. Runs entirely on this Mac." + (SystemInfo.isLowMemory ? " On this Mac (\(Int(SystemInfo.memoryGB.rounded())) GB) expect a few seconds per dictation." : " Adds about a second."))
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Model", selection: $settings.refinerModel) {
                        Text(RefinerModel.qwen3_4b.title).tag(RefinerModel.qwen3_4b)
                        Text(RefinerModel.qwen3_1_7b.title).tag(RefinerModel.qwen3_1_7b)
                        Text(RefinerModel.qwen3_0_6b.title + (SystemInfo.isLowMemory ? " · recommended here" : ""))
                            .tag(RefinerModel.qwen3_0_6b)
                    }
                    if let progress = controller.refinerDownloadProgress {
                        ProgressView(value: progress) { Text("Downloading \(Int(progress * 100))%") }
                    } else if !controller.refinerInstalled {
                        HStack {
                            Text("Download the model to turn this on").foregroundStyle(.secondary)
                            Spacer()
                            Button("Download") { controller.downloadRefiner() }
                        }
                    }
                } else {
                    Text("Needs a Mac with 16 GB of memory (this one has \(Int(SystemInfo.memoryGB.rounded())) GB). Everything else in Evoo works fully without it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Voice shortcuts") {
                Text("Say the phrase, get the text — alone or mid-sentence (“send it to my email”).")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(settings.snippets.indices, id: \.self) { i in
                    HStack(alignment: .top) {
                        TextField("Say…", text: $settings.snippets[i].trigger).frame(width: 120)
                        TextField("Type…", text: $settings.snippets[i].expansion, axis: .vertical).lineLimit(1 ... 4)
                        Button {
                            settings.snippets.remove(at: i)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("Add shortcut") { settings.snippets.append(Snippet(trigger: "", expansion: "")) }
            }

            Section("History") {
                Toggle("Keep my recent dictations on this Mac", isOn: $settings.keepHistory)
                HStack {
                    Text("\(DictationHistory.shared.entries.count) saved").foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear history") { DictationHistory.shared.clear() }
                        .disabled(DictationHistory.shared.entries.isEmpty)
                }
            }

            Section("Your writing style") {
                Toggle("Learn how I write", isOn: $settings.learnStyle)
                Text("Evoo keeps what it typed next to what you actually sent, and uses your own edits when it polishes — so it writes like you, not like a template. Stored only on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Learned from", value: "\(style.editedCount) edits · \(style.pairs.count) messages")
                ForEach(style.profiles, id: \.app) { p in
                    LabeledContent(EditWatcher.appName(p.app), value: p.summary)
                }
                ForEach(style.rewrites.keys.sorted(), id: \.self) { app in
                    LabeledContent(EditWatcher.appName(app) + " swaps",
                                   value: style.rewrites[app]!.prefix(6).map { "\($0.from) → \($0.to.isEmpty ? "(removed)" : $0.to)" }
                                       .joined(separator: ", "))
                }
                Button("Erase what Evoo learned about my style", role: .destructive) { style.erase() }
                    .disabled(style.pairs.isEmpty)
            }

            Section("Personal model (trained on this Mac)") {
                Text("With enough of your edits, Evoo fine-tunes a small add-on for its AI at night while your Mac is plugged in — so polish writes the way you do. It's tested on edits it hasn't seen and only used if it's clearly closer to you. Nothing leaves this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Use my personal model", isOn: $settings.usePersonalModel)
                LabeledContent("Your edits", value: "\(personal.editedPairs) of \(PersonalTraining.minPairs) needed")
                if let result = personal.result { LabeledContent("In use", value: result) }
                switch personal.status {
                case let .working(text): HStack { ProgressView().controlSize(.small); Text(text) }
                case let .failed(text): Text(text).font(.caption).foregroundStyle(.orange)
                case .idle: EmptyView()
                }
                HStack {
                    Button("Train now") { Task { await personal.train(controller: controller) } }
                        .disabled(personal.isBusy || personal.editedPairs < PersonalTraining.minPairs)
                    if personal.hasAdapter(for: settings.refinerModel) {
                        Button("Remove personal model", role: .destructive) {
                            personal.remove(for: settings.refinerModel)
                            controller.prepareRefiner()
                        }
                    }
                }
            }

            Section("Learning") {
                Toggle("Learn from my edits", isOn: $settings.learnFromEdits)
                Text("When you fix something Evoo typed, it learns: corrected names join your dictionary, and habits like deleting the final full stop in chat apps are remembered per app. Only learned words and counts are kept — never your text.")
                    .font(.caption).foregroundStyle(.secondary)
                if let status = controller.learningStatus {
                    LabeledContent("Last check", value: status)
                }
                let learned = settings.habits.apps.filter { $0.value.dropsFinalPeriod || $0.value.lowercasesStart }
                ForEach(learned.keys.sorted(), id: \.self) { app in
                    let h = learned[app]!
                    LabeledContent(appName(app), value: [h.dropsFinalPeriod ? "no final full stop" : nil,
                                                         h.lowercasesStart ? "lowercase start" : nil]
                            .compactMap { $0 }.joined(separator: ", "))
                }
                if !settings.habits.apps.isEmpty {
                    Button("Reset learned habits") { settings.habits = LearnedHabits() }
                }
            }

            Section("General") {
                Toggle("Show Evoo in the Dock", isOn: $settings.showInDock)
                    .onChange(of: settings.showInDock) { _, show in AppDelegate.applyDockSetting(show) }
                Toggle("Show floating pill", isOn: $settings.showPill)
                Picker("Pill position", selection: Binding(
                    get: { pillPlace },
                    set: { pillPlace = $0
                        if let p = Self.pillPlaces.first(where: { $0.name == pillPlace }) { PillModel.shared.place(x: p.x, y: p.y) }
                    })) {
                    ForEach(Self.pillPlaces, id: \.name) { Text($0.name).tag($0.name) }
                    if !Self.pillPlaces.contains(where: { $0.name == pillPlace }) { Text("Custom (dragged)").tag(pillPlace) }
                }
                Text("Or drag the pill anywhere along the bottom, or up the left or right side of the screen.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show words above the pill as you speak", isOn: $settings.livePreview)
                Toggle("Show occasional tips about features", isOn: $settings.showTips)
                Toggle("Play sounds", isOn: $settings.playSounds)
                Toggle("Restore clipboard after pasting", isOn: $settings.restoreClipboard)
                Toggle("Start Evoo at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        guard on != LoginItem.isEnabled else { return }
                        do { try LoginItem.set(on) } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LoginItem.isEnabled
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }

            if let timings = controller.lastTimings {
                Section("Last dictation") {
                    Text(timings).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            permissions.refresh()
        }
        .task {
            microphones = await Task.detached(priority: .userInitiated) { AudioDevices.inputs() }.value
            launchAtLogin = await LoginItem.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
            controller.startHotkeysIfPossible()
        }
    }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !settings.personalWords.contains(word) else { return }
        settings.personalWords.append(word)
        newWord = ""
    }

    private func appName(_ bundleID: String) -> String {
        EditWatcher.appName(bundleID)
    }
}
