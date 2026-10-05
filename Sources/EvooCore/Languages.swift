import Foundation

/// What the user speaks and how the output should be written.
public enum DictationLanguage: String, CaseIterable, Codable, Sendable {
    case english
    case hinglish
    case hindi
    // The other languages Parakeet TDT v3 speaks (same model as English, nothing extra to download).
    case spanish
    case french
    case german
    case italian
    case portuguese
    case dutch
    case polish
    case romanian
    case swedish
    case danish
    case finnish
    case hungarian
    case czech
    case slovak
    case slovenian
    case croatian
    case bulgarian
    case greek
    case estonian
    case latvian
    case lithuanian
    case maltese
    case russian
    case ukrainian

    /// The 24 European languages besides English that the built-in speech model understands.
    public static let european: [DictationLanguage] = [.spanish, .french, .german, .italian, .portuguese, .dutch, .polish, .romanian, .swedish, .danish, .finnish, .hungarian, .czech, .slovak, .slovenian, .croatian, .bulgarian, .greek, .estonian, .latvian, .lithuanian, .maltese, .russian, .ukrainian]

    public var title: String {
        switch self {
        case .english: "English"
        case .hinglish: "Hinglish"
        case .hindi: "Hindi (देवनागरी)"
        case .spanish: "Español (Spanish)"
        case .french: "Français (French)"
        case .german: "Deutsch (German)"
        case .italian: "Italiano (Italian)"
        case .portuguese: "Português (Portuguese)"
        case .dutch: "Nederlands (Dutch)"
        case .polish: "Polski (Polish)"
        case .romanian: "Română (Romanian)"
        case .swedish: "Svenska (Swedish)"
        case .danish: "Dansk (Danish)"
        case .finnish: "Suomi (Finnish)"
        case .hungarian: "Magyar (Hungarian)"
        case .czech: "Čeština (Czech)"
        case .slovak: "Slovenčina (Slovak)"
        case .slovenian: "Slovenščina (Slovenian)"
        case .croatian: "Hrvatski (Croatian)"
        case .bulgarian: "Български (Bulgarian)"
        case .greek: "Ελληνικά (Greek)"
        case .estonian: "Eesti (Estonian)"
        case .latvian: "Latviešu (Latvian)"
        case .lithuanian: "Lietuvių (Lithuanian)"
        case .maltese: "Malti (Maltese)"
        case .russian: "Русский (Russian)"
        case .ukrainian: "Українська (Ukrainian)"
        }
    }

    /// The language's English name ("Spanish").
    public var englishName: String {
        switch self {
        case .english: "English"
        case .hinglish: "Hinglish"
        case .hindi: "Hindi"
        case .spanish: "Spanish"
        case .french: "French"
        case .german: "German"
        case .italian: "Italian"
        case .portuguese: "Portuguese"
        case .dutch: "Dutch"
        case .polish: "Polish"
        case .romanian: "Romanian"
        case .swedish: "Swedish"
        case .danish: "Danish"
        case .finnish: "Finnish"
        case .hungarian: "Hungarian"
        case .czech: "Czech"
        case .slovak: "Slovak"
        case .slovenian: "Slovenian"
        case .croatian: "Croatian"
        case .bulgarian: "Bulgarian"
        case .greek: "Greek"
        case .estonian: "Estonian"
        case .latvian: "Latvian"
        case .lithuanian: "Lithuanian"
        case .maltese: "Maltese"
        case .russian: "Russian"
        case .ukrainian: "Ukrainian"
        }
    }

    /// ISO 639-1 code ("es"). Hinglish is decoded as Hindi and romanized.
    public var code: String {
        switch self {
        case .english: "en"
        case .hinglish, .hindi: "hi"
        case .spanish: "es"
        case .french: "fr"
        case .german: "de"
        case .italian: "it"
        case .portuguese: "pt"
        case .dutch: "nl"
        case .polish: "pl"
        case .romanian: "ro"
        case .swedish: "sv"
        case .danish: "da"
        case .finnish: "fi"
        case .hungarian: "hu"
        case .czech: "cs"
        case .slovak: "sk"
        case .slovenian: "sl"
        case .croatian: "hr"
        case .bulgarian: "bg"
        case .greek: "el"
        case .estonian: "et"
        case .latvian: "lv"
        case .lithuanian: "lt"
        case .maltese: "mt"
        case .russian: "ru"
        case .ukrainian: "uk"
        }
    }

    /// Language hint passed to Whisper.
    public var whisperCode: String { code }

    /// Parakeet TDT v3 covers 25 European languages — not Hindi.
    public var parakeetSupported: Bool {
        self == .english || Self.european.contains(self)
    }

    /// Evoo's rules (self-corrections, fillers, numbers, lists, spoken commands) and the AI polish are written for
    /// English. In other European languages they'd misfire ("no" is a correction cue in English, a normal word in
    /// Spanish), so those get the speech model's own text, with your names fixed.
    public var usesEnglishRules: Bool {
        !Self.european.contains(self)
    }

    /// Extra instruction for the refinement model.
    var outputInstruction: String {
        switch self {
        case .english:
            "Write the result in English."
        case .hinglish:
            """
            The speaker mixes Hindi and English (Hinglish). Write Hindi words in Roman (Latin) script \
            the way people type in chat, e.g. "kal milte hain". Never use Devanagari. Keep English words in English.
            """
        case .hindi:
            "Write the result in Hindi using Devanagari script. Keep English technical words as they are."
        default:
            "Write the result in \(englishName)."
        }
    }
}

public enum ASREngineID: String, CaseIterable, Codable, Sendable {
    case parakeet
    case whisper
    /// The Hinglish add-on (Whisper fine-tuned to write Roman Hinglish).
    case hinglish

    public var title: String {
        switch self {
        case .parakeet: "Parakeet TDT v3 (fastest, English + EU)"
        case .whisper: "Whisper large-v3 turbo (multilingual)"
        case .hinglish: "Hinglish add-on (Whisper, fine-tuned)"
        }
    }

    public var license: String {
        switch self {
        case .parakeet: "NVIDIA Parakeet TDT 0.6B v3 — CC-BY-4.0"
        case .whisper: "OpenAI Whisper — MIT"
        case .hinglish: "Oriserve Whisper-Hindi2Hinglish — Apache-2.0"
        }
    }
}

public enum EnginePreference: String, CaseIterable, Codable, Sendable {
    case automatic
    case parakeet
    case whisper

    public var title: String {
        switch self {
        case .automatic: "Automatic (by language)"
        case .parakeet: ASREngineID.parakeet.title
        case .whisper: ASREngineID.whisper.title
        }
    }

    public func resolve(for language: DictationLanguage) -> ASREngineID {
        switch self {
        case .automatic: language == .hinglish ? .hinglish : language.parakeetSupported ? .parakeet : .whisper
        case .parakeet: language.parakeetSupported ? .parakeet : .whisper
        case .whisper: .whisper
        }
    }
}
