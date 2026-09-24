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
                    ForEach(DictationLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Microphone", selection: $settings.microphoneUID) {
                    Text("System default").tag(String?.none)
                    ForEach(microphones) { Text($0.name).tag(Optional($0.id)) }
                }
            }

            Section("Speech model") {
                Picker("Engine", selection: $settings.engine) {
                    ForEach(EnginePreference.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                LabeledContent("In use", value: settings.resolvedEngine.title)
                if let status = controller.modelStatus {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Personal dictionary") {
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

            Section("General") {
                Toggle("Show floating pill", isOn: $settings.showPill)
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
        .frame(width: 480, height: 640)
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
}
