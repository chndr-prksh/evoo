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
    /// CoreAudio device UID; nil = system default input.
    @Published var microphoneUID: String? { didSet { save(microphoneUID, "microphoneUID") } }
    @Published var showPill: Bool { didSet { save(showPill, "showPill") } }
    @Published var playSounds: Bool { didSet { save(playSounds, "playSounds") } }
    @Published var restoreClipboard: Bool { didSet { save(restoreClipboard, "restoreClipboard") } }
    /// Names and terms to recognize correctly ("Divya", "Kubernetes").
    @Published var personalWords: [String] { didSet { save(personalWords, "personalWords") } }

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
        refinerModel = value("refinerModel", .qwen3_1_7b)
        microphoneUID = UserDefaults.standard.string(forKey: "microphoneUID")
        showPill = bool("showPill", true)
        playSounds = bool("playSounds", true)
        restoreClipboard = bool("restoreClipboard", true)
        personalWords = UserDefaults.standard.stringArray(forKey: "personalWords") ?? []
    }

    var resolvedEngine: ASREngineID { engine.resolve(for: language) }

    private func save(_ value: Any?, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
