import EvooCore
import Foundation

/// User preferences, persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var activationMode: ActivationMode { didSet { save(activationMode.rawValue, "activationMode") } }
    @Published var language: DictationLanguage { didSet { save(language.rawValue, "language") } }
    @Published var engine: EnginePreference { didSet { save(engine.rawValue, "engine") } }
    @Published var refinementEnabled: Bool { didSet { save(refinementEnabled, "refinementEnabled") } }
    @Published var refinerModel: RefinerModel { didSet { save(refinerModel.rawValue, "refinerModel") } }
    /// 16 GB+ Macs: a local LLM polishes every dictation and powers "rewrite by voice".
    @Published var smartCleanup: Bool { didSet { save(smartCleanup, "smartCleanup") } }
    /// CoreAudio device UID; nil = system default input.
    @Published var microphoneUID: String? { didSet { save(microphoneUID, "microphoneUID") } }
    @Published var showPill: Bool { didSet { save(showPill, "showPill") } }
    @Published var playSounds: Bool { didSet { save(playSounds, "playSounds") } }
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
    /// Occasional tips by the pill introducing one feature at a time.
    @Published var showTips: Bool { didSet { save(showTips, "showTips") } }
    @Published var dictationCount: Int { didSet { save(dictationCount, "dictationCount") } }
    @Published var shownTips: [String] { didSet { save(shownTips, "shownTips") } }
    /// Keep recent dictations on this Mac so they can be searched and re-used.
    @Published var keepHistory: Bool { didSet { save(keepHistory, "keepHistory") } }
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
        language = value("language", .english)
        engine = value("engine", .automatic)
        refinementEnabled = bool("refinementEnabled", true)
        refinerModel = value("refinerModel", SystemInfo.canRunSmartCleanup ? .qwen3_4b : .qwen3_1_7b)
        smartCleanup = bool("smartCleanup", false) && SystemInfo.canRunSmartCleanup
        microphoneUID = UserDefaults.standard.string(forKey: "microphoneUID")
        showPill = bool("showPill", true)
        playSounds = bool("playSounds", true)
        restoreClipboard = bool("restoreClipboard", true)
        personalWords = UserDefaults.standard.stringArray(forKey: "personalWords") ?? []
        if !Features.multilingual {
            language = .english
            engine = .automatic
            refinementEnabled = false
        }
        formatText = bool("formatText", true)
        fastestModel = bool("fastestModel", false)
        useScreenContext = bool("useScreenContext", true)
        learnFromEdits = bool("learnFromEdits", true)
        snippets = UserDefaults.standard.data(forKey: "snippets")
            .flatMap { try? JSONDecoder().decode([Snippet].self, from: $0) } ?? []
        keepHistory = bool("keepHistory", true)
        showTips = bool("showTips", true)
        dictationCount = UserDefaults.standard.integer(forKey: "dictationCount")
        shownTips = UserDefaults.standard.stringArray(forKey: "shownTips") ?? []
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
