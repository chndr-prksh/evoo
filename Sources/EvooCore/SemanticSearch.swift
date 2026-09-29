import Foundation
import NaturalLanguage

/// Finds past dictations and notes by meaning, not just exact words ("the invoice" also finds "billing for
/// March"), using Apple's on-device sentence embeddings. Falls back to word matching if they're unavailable.
public enum SemanticSearch {
    /// Indices of `texts`, best match first, dropping ones that are clearly unrelated.
    public static func rank(_ query: String, in texts: [String], limit: Int = 50) -> [Int] {
        let q = query.lowercased()
        let qWords = Set(q.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
        let embedding = NLEmbedding.sentenceEmbedding(for: .english)
        let qVector = embedding?.vector(for: q)
        let scored: [(Int, Double)] = texts.enumerated().map { i, text in
            let lower = text.lowercased()
            var score = 0.0
            if let qVector, let v = embedding?.vector(for: String(lower.prefix(1000))) {
                score += cosine(qVector, v)
            }
            let words = Set(lower.split { !$0.isLetter && !$0.isNumber }.map(String.init))
            if !qWords.isEmpty { score += Double(qWords.intersection(words).count) / Double(qWords.count) }
            if lower.contains(q) { score += 1 }
            return (i, score)
        }
        let threshold = embedding == nil ? 0.01 : 0.35
        return scored.filter { $0.1 >= threshold }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// Relevance of `query` to each text (same scoring as `rank`, unfiltered, in input order).
    public static func scores(_ query: String, in texts: [String]) -> [Double] {
        let q = query.lowercased()
        let qWords = Set(q.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 3 })
        let embedding = NLEmbedding.sentenceEmbedding(for: .english)
        let qVector = embedding?.vector(for: String(q.suffix(1_500)))
        return texts.map { text in
            let lower = text.lowercased()
            var score = 0.0
            if let qVector, let v = embedding?.vector(for: String(lower.prefix(1_500))) { score += cosine(qVector, v) }
            let words = Set(lower.split { !$0.isLetter && !$0.isNumber }.map(String.init))
            if !qWords.isEmpty { score += Double(qWords.intersection(words).count) / Double(qWords.count) }
            return score
        }
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0 ..< min(a.count, b.count) {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        return na > 0 && nb > 0 ? dot / (na.squareRoot() * nb.squareRoot()) : 0
    }
}

/// Subtitles (.srt) from word timings: short lines, broken at sentence ends or every ~6 seconds.
public enum Subtitles {
    public struct Timed: Sendable {
        public var text: String
        public var start: Double
        public var end: Double

        public init(text: String, start: Double, end: Double) {
            self.text = text
            self.start = start
            self.end = end
        }
    }

    /// Token pieces (SentencePiece "▁word" or " word") → .srt text.
    public static func srt(_ tokens: [Timed], maxChars: Int = 42, maxSeconds: Double = 6) -> String {
        var cues: [(String, Double, Double)] = []
        var text = "", start = 0.0, end = 0.0
        for t in tokens {
            let piece = t.text.replacingOccurrences(of: "▁", with: " ")
            if text.isEmpty { start = t.start }
            let startsWord = piece.hasPrefix(" ")
            if startsWord, !text.isEmpty,
               text.count + piece.count > maxChars || t.end - start > maxSeconds || ".?!".contains(text.last!)
            {
                cues.append((text, start, end))
                text = ""
                start = t.start
            }
            text += text.isEmpty ? piece.trimmingCharacters(in: .whitespaces) : piece
            end = t.end
        }
        if !text.isEmpty { cues.append((text, start, end)) }
        return cues.enumerated().map { i, cue in
            "\(i + 1)\n\(stamp(cue.1)) --> \(stamp(cue.2))\n\(cue.0.trimmingCharacters(in: .whitespaces))\n"
        }.joined(separator: "\n")
    }

    static func stamp(_ t: Double) -> String {
        let ms = Int((t * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60000 % 60, ms / 1000 % 60, ms % 1000)
    }
}
