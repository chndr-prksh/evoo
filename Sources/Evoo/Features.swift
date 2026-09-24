/// Build-time feature switches.
enum Features {
    /// Hindi / Hinglish (Whisper + local LLM). Off for now: Evoo ships English-only, tuned for speed.
    /// Turning it back on restores the language picker, Whisper, and the local AI refiner.
    static let multilingual = false
}
