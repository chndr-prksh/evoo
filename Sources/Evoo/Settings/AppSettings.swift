import EvooCore
import Foundation

/// User preferences, persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var activationMode: ActivationMode { didSet { save(activationMode.rawValue, "activationMode") } }
    @Published var language: DictationLanguage { didSet { save(language.rawValue, "language"); Features.noteUsed(language) } }
    @Published var engine: EnginePreference { didSet { save(engine.rawValue, "engine") } }
    @Published var refinementEnabled: Bool { didSet { save(refinementEnabled, "refinementEnabled") } }
    @Published var refinerModel: RefinerModel { didSet { save(refinerModel.rawValue, "refinerModel") } }
    /// 16 GB+ Macs: a local LLM polishes every dictation and powers "rewrite by voice".
    @Published var smartCleanup: Bool { didSet { save(smartCleanup, "smartCleanup") } }
    /// CoreAudio device UID; nil = system default input.
    @Published var microphoneUID: String? { didSet { save(microphoneUID, "microphoneUID") } }
    @Published var showPill: Bool { didSet { save(showPill, "showPill") } }
    @Published var playSounds: Bool { didSet { save(playSounds, "playSounds") } }
    /// Mic runs between dictations so fn starts instantly (and keeps the 0.3 s before the press).
    @Published var keepMicReady: Bool { didSet { save(keepMicReady, "keepMicReady") } }
    /// Evoo in the Dock with its main window (like Wispr Flow); off = menu bar only.
    @Published var showInDock: Bool { didSet { save(showInDock, "showInDock") } }
    /// Lifetime totals for Home (history itself only keeps the last 500 dictations).
    @Published var wordsDictated: Int { didSet { save(wordsDictated, "wordsDictated") } }
    @Published var secondsDictated: Double { didSet { save(secondsDictated, "secondsDictated") } }
    @Published var restoreClipboard: Bool { didSet { save(restoreClipboard, "restoreClipboard") } }
    /// Names and terms to recognize correctly ("Divya", "Kubernetes").
    @Published var personalWords: [String] { didSet { save(personalWords, "personalWords") } }
    /// Lists, spoken line breaks and emails, styled per app (Markdown, bullets, or one line in terminals).
    @Published var formatText: Bool { didSet { save(formatText, "formatText") } }
    /// Parakeet 110M instead of 0.6B: about 2× faster, less accurate with names.
    @Published var fastestModel: Bool { didSet { save(fastestModel, "fastestModel") } }
    /// Spell names seen on screen (chat header, recipients, text near the cursor) correctly.
    @Published var useScreenContext: Bool { didSet { save(useScreenContext, "useScreenContext") } }
    /// Learn names and per-app habits from how the user edits dictated text.
    @Published var learnFromEdits: Bool { didSet { save(learnFromEdits, "learnFromEdits") } }
    @Published var snippets: [Snippet] {
        didSet { defaults.set(try? JSONEncoder().encode(snippets), forKey: "snippets") }
    }
    /// "open Slack", "search Google for …" act instead of typing.
    @Published var appCommands: Bool { didSet { save(appCommands, "appCommands") } }
    /// Apps and sites the user added for voice commands.
    @Published var customApps: [AppTarget] {
        didSet { defaults.set(try? JSONEncoder().encode(customApps), forKey: "customApps") }
    }
    /// Learn unusual words seen on screen across dictations (names, products, projects).
    @Published var learnFromScreen: Bool { didSet { save(learnFromScreen, "learnFromScreen") } }
    @Published var screenLexicon: ScreenLexicon {
        didSet { defaults.set(try? JSONEncoder().encode(screenLexicon), forKey: "screenLexicon") }
    }
    /// Words added to the dictionary from the screen, so Settings can list them separately.
    @Published var screenLearned: [String] { didSet { save(screenLearned, "screenLearned") } }
    /// Occasional tips by the pill introducing one feature at a time.
    @Published var showTips: Bool { didSet { save(showTips, "showTips") } }
    @Published var dictationCount: Int { didSet { save(dictationCount, "dictationCount") } }
    @Published var shownTips: [String] { didSet { save(shownTips, "shownTips") } }
    /// Dictation count when the last tip was shown.
    @Published var lastTipAt: Int { didSet { save(lastTipAt, "lastTipAt") } }
    /// Features the user has used — their tips are never shown.
    @Published var usedFeatures: [String] { didSet { save(usedFeatures, "usedFeatures") } }
    /// Keep recent dictations on this Mac so they can be searched and re-used.
    @Published var keepHistory: Bool { didSet { save(keepHistory, "keepHistory") } }
    /// Learn how the user writes from their edits (Layer 1: examples + style in the polish prompt).
    @Published var learnStyle: Bool { didSet { save(learnStyle, "learnStyle") } }
    /// Use the add-on fine-tuned on this Mac from the user's edits (Layer 2), when there is one.
    @Published var usePersonalModel: Bool { didSet { save(usePersonalModel, "usePersonalModel") } }
    @Published var habits: LearnedHabits {
        didSet { defaults.set(try? JSONEncoder().encode(habits), forKey: "habits") }
    }

    private init() {
        func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            (UserDefaults.standard.string(forKey: key)).flatMap(T.init(rawValue:)) ?? fallback
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
        }
        activationMode = value("activationMode", .hybrid)
        // English unless the Hinglish add-on is installed; Hindi (Devanagari) and the old Whisper + LLM path are off.
        let saved: DictationLanguage = value("language", .english)
        language = Features.languages.contains(saved) ? saved : .english
        engine = value("engine", .automatic)
        refinementEnabled = bool("refinementEnabled", true)
        // Dictation polish: the 4B model polishes ~4 words/s on an 8 GB Mac — slower than people speak — so smaller
        // Macs use a small model. Class notes always use the 4B.
        // Measured on an 8 GB M1: 0.6B polishes a sentence in ~0.76 s vs 1.7 s for the 1.7B, same golden score (68/69).
        refinerModel = value("refinerModel", SystemInfo.isLowMemory ? .qwen3_0_6b : .qwen3_4b)
        smartCleanup = bool("smartCleanup", false) && SystemInfo.canRunSmartCleanup
        microphoneUID = UserDefaults.standard.string(forKey: "microphoneUID")
        showPill = bool("showPill", true)
        playSounds = bool("playSounds", true)
        keepMicReady = bool("keepMicReady", false)
        showInDock = bool("showInDock", true)
        wordsDictated = UserDefaults.standard.integer(forKey: "wordsDictated")
        secondsDictated = UserDefaults.standard.double(forKey: "secondsDictated")
        restoreClipboard = bool("restoreClipboard", true)
        personalWords = UserDefaults.standard.stringArray(forKey: "personalWords") ?? []
        engine = .automatic
        refinementEnabled = false
        formatText = bool("formatText", true)
        // Accurate by default: the golden set scores 67/69 vs 58/69 for the 110M model (it mishears short commands —
        // "Mute" → "Mud", "space bar" → "face bar"), and streaming means long dictations don't wait for it anyway.
        fastestModel = bool("fastestModel", false)
        useScreenContext = bool("useScreenContext", true)
        learnFromEdits = bool("learnFromEdits", true)
        snippets = UserDefaults.standard.data(forKey: "snippets")
            .flatMap { try? JSONDecoder().decode([Snippet].self, from: $0) } ?? []
        keepHistory = bool("keepHistory", true)
        learnStyle = bool("learnStyle", true)
        usePersonalModel = bool("usePersonalModel", true)
        showTips = bool("showTips", true)
        learnFromScreen = bool("learnFromScreen", true)
        screenLexicon = UserDefaults.standard.data(forKey: "screenLexicon")
            .flatMap { try? JSONDecoder().decode(ScreenLexicon.self, from: $0) } ?? ScreenLexicon()
        screenLearned = UserDefaults.standard.stringArray(forKey: "screenLearned") ?? []
        dictationCount = UserDefaults.standard.integer(forKey: "dictationCount")
        shownTips = UserDefaults.standard.stringArray(forKey: "shownTips") ?? []
        lastTipAt = UserDefaults.standard.integer(forKey: "lastTipAt")
        usedFeatures = UserDefaults.standard.stringArray(forKey: "usedFeatures") ?? []
        appCommands = bool("appCommands", true)
        customApps = UserDefaults.standard.data(forKey: "customApps")
            .flatMap { try? JSONDecoder().decode([AppTarget].self, from: $0) } ?? []
        habits = UserDefaults.standard.data(forKey: "habits")
            .flatMap { try? JSONDecoder().decode(LearnedHabits.self, from: $0) } ?? LearnedHabits()
    }

    var resolvedEngine: ASREngineID { engine.resolve(for: language) }

    private func save(_ value: Any?, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
