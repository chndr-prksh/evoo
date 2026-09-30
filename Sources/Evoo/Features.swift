import EvooCore
import EvooSpeech

/// Feature switches.
enum Features {
    /// Language switching (English / Hinglish): available once the Hinglish add-on is downloaded (Settings).
    /// English always keeps its own model (Parakeet) and pipeline.
    static var multilingual: Bool { HinglishAddon.isInstalled }
    /// Hindi in Devanagari stays hidden until it's good enough.
    static let languages: [DictationLanguage] = [.english, .hinglish]
}
