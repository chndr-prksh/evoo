import Foundation

/// Deterministic cleanup applied to raw ASR output before (or instead of) LLM refinement.
public enum TextCleaner {
    /// Phrases Whisper is known to hallucinate on silence or noise.
    static let hallucinations: Set<String> = [
        "thank you", "thank you.", "thanks for watching", "thanks for watching!",
        "thank you for watching", "thank you for watching.", "please subscribe",
        "subscribe to my channel", "you", "bye", "bye.", ".", "…",
    ]

    public static func clean(_ raw: String) -> String {
        var text = raw
        // [BLANK_AUDIO], [Music], (inaudible), ♪ …
        text = text.replacingOccurrences(of: #"\[[^\]]*\]|\((?:music|inaudible|silence|applause|laughs?)\)|♪+"#,
                                         with: " ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if hallucinations.contains(text.lowercased()) { return "" }
        // "p.m. on the 21st": the sentence goes on — the dot is the abbreviation's, not a full stop.
        text = text.replacingOccurrences(of: #"\b([AaPp])\.\s?([Mm])\.(?=\s+[a-z])"#, with: "$1.$2",
                                         options: .regularExpression)
        // A speech model sometimes echoes the last word: "Click Send. Send", "T. T. T. T."
        text = text.replacingOccurrences(of: #"\b([\w']+)\.(?:\s+\1\.?)+$"#, with: "$1.",
                                         options: [.regularExpression, .caseInsensitive])
        return text
    }
}

extension TextCleaner {
    /// Writes times the way people type them, after number formatting:
    /// "04:00 P.M." → "4 PM", "04:30 p.m." → "4:30 PM", and drops the doubled full stop in "p.m..".
    public static func tidyTimes(_ text: String) -> String {
        var out = text
        // "p.m." (both dots) or "PM" — never swallow a full stop that follows "PM".
        let meridiem = #"\s?([AaPp])(?:\.\s?[Mm]\.|\s?[Mm]\b)"#
        // "7.30 p.m." → "7:30 p.m." (a dot between hour and minutes is a speech-model habit).
        out = out.replacingOccurrences(of: #"\b(\d{1,2})\.(\d{2})(?=\s?[AaPp]\.?\s?[Mm]\b)"#, with: "$1:$2",
                                       options: .regularExpression)
        // "p.m. on the 21st": the sentence goes on, so the second dot is only the abbreviation's.
        out = out.replacingOccurrences(of: #"\b([AaPp])\.\s?[Mm]\.(?=\s+[a-z])"#, with: "$1M", options: .regularExpression)
        // "8 p.m. Then…": the second dot also ends the sentence.
        out = out.replacingOccurrences(of: #"([AaPp])\.\s?[Mm]\.(?=\s+[A-Z])"#, with: "$1M.", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\b0?(\d{1,2}):00"# + meridiem, with: "$1 $2M", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\b0?(\d{1,2}):(\d{2})"# + meridiem, with: "$1:$2 $3M", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\b(\d{1,2})"# + meridiem, with: "$1 $2M", options: .regularExpression)
        out = out.replacingOccurrences(of: "aM", with: "AM").replacingOccurrences(of: "pM", with: "PM")
        out = out.replacingOccurrences(of: #"(?<!\.)\.\.(?!\.)"#, with: ".", options: .regularExpression)
        // A sentence-final "p.m." was also the full stop: keep one.
        if text.hasSuffix("."), let last = out.last, !".?!".contains(last) { out += "." }
        return out
    }
}

public enum AudioStats {
    /// Root-mean-square level of the clip.
    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// True when the loudest 100 ms window is below the threshold — nobody spoke.
    /// Seconds of the clip that sound like voice (20 ms frames above `threshold`). Speech is sustained; the
    /// click of the fn key or a tap on the desk lasts a few tens of milliseconds.
    public static func voicedSeconds(_ samples: [Float], sampleRate: Int = 16_000, threshold: Float = 0.008) -> Double {
        let frame = sampleRate / 50
        var voiced = 0
        var i = 0
        while i + frame <= samples.count {
            if rms(Array(samples[i ..< i + frame])) >= threshold { voiced += 1 }
            i += frame
        }
        return Double(voiced) * 0.02
    }

    /// Nothing worth transcribing: quiet, or only a click (the model would turn a key click into "Yeah.").
    public static func hasNoSpeech(_ samples: [Float], sampleRate: Int = 16_000) -> Bool {
        isLikelySilent(samples, sampleRate: sampleRate) || voicedSeconds(samples, sampleRate: sampleRate) < 0.15
    }

    public static func isLikelySilent(_ samples: [Float], sampleRate: Int = 16_000, threshold: Float = 0.006) -> Bool {
        let window = sampleRate / 10
        guard samples.count >= window else { return true }
        var peak: Float = 0
        var i = 0
        while i + window <= samples.count {
            peak = max(peak, rms(Array(samples[i ..< i + window])))
            i += window
        }
        return peak < threshold
    }

    /// The part of the clip that contains speech, padded a little so soft word edges survive.
    /// People hold fn before they start and after they finish; the model shouldn't pay for that silence.
    /// Returns nil when there's no speech at all.
    public static func speechRange(_ samples: [Float], sampleRate: Int = 16_000, threshold: Float = 0.008,
                                   leadPad: Double = 0.15, tailPad: Double = 0.25) -> Range<Int>?
    {
        let frame = sampleRate / 50 // 20 ms
        guard samples.count >= frame else { return nil }
        var first: Int?
        var last = 0
        var i = 0
        while i + frame <= samples.count {
            if rms(Array(samples[i ..< i + frame])) >= threshold {
                if first == nil { first = i }
                last = i + frame
            }
            i += frame
        }
        guard let first else { return nil }
        let start = max(0, first - Int(leadPad * Double(sampleRate)))
        let end = min(samples.count, last + Int(tailPad * Double(sampleRate)))
        return start ..< end
    }

    /// True when the last `seconds` of the clip are silent — the speaker has paused.
    public static func endsInPause(_ samples: [Float], seconds: Double = 0.3, sampleRate: Int = 16_000,
                                   threshold: Float = 0.008) -> Bool
    {
        let n = Int(seconds * Double(sampleRate))
        guard samples.count > n else { return false }
        let frame = sampleRate / 50
        var i = samples.count - n
        while i + frame <= samples.count {
            if rms(Array(samples[i ..< i + frame])) >= threshold { return false }
            i += frame
        }
        return true
    }
}
