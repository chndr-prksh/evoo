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
        return text
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
}
