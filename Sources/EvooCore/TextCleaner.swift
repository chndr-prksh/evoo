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

    static let scales: [String: Decimal] = [
        "hundred": 100, "thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000,
        "trillion": 1_000_000_000_000,
    ]
    static let scaleWords = "hundred|thousand|million|billion|trillion"

    /// "40 million", "$3 million", "3 million dollars": the speech model already wrote the digits. The number
    /// normalizer only reads spelled-out numbers and turns the lone scale word into digits ("40 1000000 rows"),
    /// so these amounts are written here and swapped for placeholders until it has run.
    public static func maskScaledNumbers(_ text: String, into restore: inout [(String, String)]) -> String {
        let pattern = #"(?i)(\$\s?)?\b(\d{1,3}(?:,\d{3})+|\d+)(\.\d+)?\s+("# + scaleWords
            + #")\b(\s+(?:dollars?|bucks)\b)?"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        var out = text
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(m.range, in: text), let num = Range(m.range(at: 2), in: text),
                  let scale = Range(m.range(at: 4), in: text) else { continue }
            let number = String(text[num]) + (Range(m.range(at: 3), in: text).map { String(text[$0]) } ?? "")
            let amount = number + " " + text[scale].lowercased()
            let isMoney = m.range(at: 1).location != NSNotFound || m.range(at: 5).location != NSNotFound
            let written: String?
            if isMoney {
                written = dollars(amount)
            } else if text[scale].lowercased() == "hundred" {
                written = plain(amount) // "3 hundred" → "300", as the normalizer writes "three hundred"
            } else {
                written = amount // "40 million", as the normalizer writes "forty million"
            }
            guard let written else { continue }
            let placeholder = "evoomoney\(restore.count)x"
            restore.append((placeholder, written))
            out.replaceSubrange(Range(m.range, in: out) ?? whole, with: placeholder)
        }
        return out
    }

    /// A dollar amount the way people type it: "1200" → "$1,200", "3 thousand" → "$3,000",
    /// "2.5 million" → "$2.5 million". Nil when `amount` is not a number with an optional scale word.
    public static func dollars(_ amount: String) -> String? {
        let parts = amount.trimmingCharacters(in: .whitespaces).lowercased().split(separator: " ").map(String.init)
        guard let first = parts.first, parts.count <= 2 else { return nil }
        if parts.count == 2, ["million", "billion", "trillion"].contains(parts[1]) {
            guard number(first) != nil else { return nil }
            return "$" + first + " " + parts[1]
        }
        return plain(amount).map { "$" + $0 }
    }

    /// "3 thousand" → "3,000", "1200" → "1,200", "2.5 hundred" → "250".
    static func plain(_ amount: String) -> String? {
        let parts = amount.trimmingCharacters(in: .whitespaces).lowercased().split(separator: " ").map(String.init)
        guard let first = parts.first, parts.count <= 2, var value = number(first) else { return nil }
        if parts.count == 2 {
            guard let scale = scales[parts[1]] else { return nil }
            value *= scale
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.locale = Locale(identifier: "en_US")
        return f.string(from: value as NSDecimalNumber)
    }

    /// "1,200" → 1200, "2.5" → 2.5; nil for anything else.
    static func number(_ s: String) -> Decimal? {
        guard s.range(of: #"^(\d{1,3}(,\d{3})+|\d+)(\.\d+)?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: s.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX"))
    }
}

public enum AudioStats {
    /// Root-mean-square level of the clip.
    public static func rms(_ samples: [Float]) -> Float {
        rms(samples[...])
    }

    /// Without copying: the checks below run over whole recordings (minutes of audio) in 20 ms frames.
    public static func rms(_ samples: ArraySlice<Float>) -> Float {
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
            if rms(samples[i ..< i + frame]) >= threshold { voiced += 1 }
            i += frame
        }
        return Double(voiced) * 0.02
    }

    /// The loudest 100 ms of the clip (0 = silence; normal speech is around 0.02–0.2).
    public static func peakLevel(_ samples: [Float], sampleRate: Int = 16_000) -> Float {
        let window = sampleRate / 10
        var peak: Float = 0
        var i = 0
        while i + window <= samples.count {
            peak = max(peak, rms(samples[i ..< i + window]))
            i += window
        }
        return peak
    }

    /// Nothing worth transcribing: quiet, or only a click (the model would turn a key click into "Yeah.").
    public static func hasNoSpeech(_ samples: [Float], sampleRate: Int = 16_000, voiced: Double? = nil) -> Bool {
        (voiced ?? voicedSeconds(samples, sampleRate: sampleRate)) < 0.15 || isLikelySilent(samples, sampleRate: sampleRate)
    }

    public static func isLikelySilent(_ samples: [Float], sampleRate: Int = 16_000, threshold: Float = 0.006) -> Bool {
        let window = sampleRate / 10
        guard samples.count >= window else { return true }
        var peak: Float = 0
        var i = 0
        while i + window <= samples.count {
            peak = max(peak, rms(samples[i ..< i + window]))
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
            if rms(samples[i ..< i + frame]) >= threshold {
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
            if rms(samples[i ..< i + frame]) >= threshold { return false }
            i += frame
        }
        return true
    }
}
