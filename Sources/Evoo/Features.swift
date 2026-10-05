import EvooCore
import EvooSpeech
import Foundation

/// Feature switches.
enum Features {
    /// Every language offered in Settings: English, the 24 other European languages the built-in speech model
    /// understands, and Hinglish once its add-on is downloaded. (Hindi in Devanagari stays hidden until it's good
    /// enough.) English always keeps its own rules and pipeline.
    static var languages: [DictationLanguage] {
        [.english] + (HinglishAddon.isInstalled ? [.hinglish] : [])
            + DictationLanguage.european.sorted { $0.englishName < $1.englishName }
    }

    /// The languages in the quick switchers (pill, menu bar, main window): English plus the ones you've used.
    static var quickLanguages: [DictationLanguage] {
        let used = Set(UserDefaults.standard.stringArray(forKey: "usedLanguages") ?? [])
        return languages.filter { $0 == .english || $0 == .hinglish || used.contains($0.rawValue) }
    }

    /// Whether to show the quick language switchers at all.
    static var multilingual: Bool { quickLanguages.count > 1 }

    static func noteUsed(_ language: DictationLanguage) {
        guard language != .english else { return }
        var used = UserDefaults.standard.stringArray(forKey: "usedLanguages") ?? []
        if !used.contains(language.rawValue) { used.append(language.rawValue) }
        UserDefaults.standard.set(used, forKey: "usedLanguages")
    }
}
