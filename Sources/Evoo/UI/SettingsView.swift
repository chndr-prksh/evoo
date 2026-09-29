import EvooCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissions: Permissions
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var microphones = AudioDevices.inputs()
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
                if Features.multilingual {
                    Picker("Language", selection: $settings.language) {
                        ForEach(DictationLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Toggle("Fastest speech model", isOn: $settings.fastestModel)
                Text(settings.fastestModel
                    ? "Parakeet 110M: about 2× faster, but less accurate with names and casing."
                    : "Parakeet 0.6B: most accurate. Text is usually ready the instant you release fn.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Format lists, line breaks and emails", isOn: $settings.formatText)
                if settings.formatText {
                    Text("Say “…buy bread, eggs, milk” for bullets, “first… second… third…” for steps, “new line” / “new paragraph” for breaks. Styled per app: Markdown in Notion, editors and browsers; • bullets in Mail, Notes and Slack; always one line in Terminal.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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

            if Features.multilingual {
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
                    Text("A local model tidies what you said — corrections, grammar, messy phrasing — after Evoo's rules. Also enables rewrite by voice: select text, hold fn, say “make this more formal”, “shorten this”, “translate to Hindi”. Runs entirely on this Mac." + (SystemInfo.isLowMemory ? " On this Mac (\(Int(SystemInfo.memoryGB.rounded())) GB) expect a few seconds per dictation." : " Adds about a second."))
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Model", selection: $settings.refinerModel) {
                        Text(RefinerModel.qwen3_4b.title).tag(RefinerModel.qwen3_4b)
                        Text(RefinerModel.qwen3_1_7b.title).tag(RefinerModel.qwen3_1_7b)
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
                Toggle("Show floating pill", isOn: $settings.showPill)
                Toggle("Show occasional tips about features", isOn: $settings.showTips)
                Toggle("Play sounds", isOn: $settings.playSounds)
                Toggle("Restore clipboard after pasting", isOn: $settings.restoreClipboard)
                Toggle("Start Evoo at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
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
            microphones = AudioDevices.inputs()
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
