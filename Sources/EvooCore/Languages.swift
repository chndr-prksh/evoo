import Foundation

/// What the user speaks and how the output should be written.
public enum DictationLanguage: String, CaseIterable, Codable, Sendable {
    case english
    case hinglish
    case hindi

    public var title: String {
        switch self {
        case .english: "English"
        case .hinglish: "Hinglish"
        case .hindi: "Hindi (देवनागरी)"
        }
    }

    /// Language hint passed to Whisper. Hinglish is decoded as Hindi and romanized by the refiner.
    public var whisperCode: String {
        switch self {
        case .english: "en"
        case .hinglish, .hindi: "hi"
        }
    }

    /// Parakeet TDT v3 covers 25 European languages — not Hindi.
    public var parakeetSupported: Bool {
        self == .english
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
        case .automatic: language == .english ? .parakeet : language == .hinglish ? .hinglish : .whisper
        case .parakeet: language.parakeetSupported ? .parakeet : .whisper
        case .whisper: .whisper
        }
    }
}
