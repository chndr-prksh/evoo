package app.evoo.core

/** Removes speech-model noise before the rules run — a port of the Mac app's TextCleaner. */
object TextCleaner {
    /** Phrases speech models are known to make up on silence or noise. */
    private val hallucinations = setOf(
        "thank you", "thank you.", "thanks for watching", "thanks for watching!",
        "thank you for watching", "thank you for watching.", "please subscribe",
        "subscribe to my channel", "you", "bye", "bye.", ".", "…",
    )

    fun clean(raw: String): String {
        var text = raw
        // [BLANK_AUDIO], [Music], (inaudible), ♪ …
        text = text.replace(Regex("(?i)\\[[^\\]]*\\]|\\((?:music|inaudible|silence|applause|laughs?)\\)|♪+"), " ")
        text = text.replace(Regex("\\s+"), " ").trim()
        if (text.lowercase() in hallucinations) return ""
        // "p.m. on the 21st": the sentence goes on — the dot is the abbreviation's, not a full stop.
        text = text.replace(Regex("\\b([AaPp])\\.\\s?([Mm])\\.(?=\\s+[a-z])"), "$1.$2")
        // A speech model sometimes echoes the last word: "Click Send. Send", "T. T. T. T."
        text = text.replace(Regex("(?i)\\b([\\w']+)\\.(?:\\s+\\1\\.?)+$"), "$1.")
        return text
    }
}

/** Decides whether a recording holds speech at all — a port of the Mac app's AudioStats. */
object AudioStats {
    private fun rms(samples: FloatArray, from: Int, to: Int): Float {
        if (to <= from) return 0f
        var sum = 0.0
        for (i in from until to) sum += samples[i] * samples[i]
        return kotlin.math.sqrt(sum / (to - from)).toFloat()
    }

    /** Seconds of the clip that sound like voice (20 ms frames above `threshold`). */
    fun voicedSeconds(samples: FloatArray, sampleRate: Int = 16_000, threshold: Float = 0.008f): Double {
        val frame = sampleRate / 50
        var voiced = 0
        var i = 0
        while (i + frame <= samples.size) {
            if (rms(samples, i, i + frame) >= threshold) voiced += 1
            i += frame
        }
        return voiced * 0.02
    }

    /** Nothing worth transcribing: quiet, or only a tap (the model would turn a click into "Yeah."). */
    fun hasNoSpeech(samples: FloatArray, sampleRate: Int = 16_000): Boolean =
        voicedSeconds(samples, sampleRate) < 0.15

    /** The part of the clip that contains speech, padded a little so soft word edges survive. */
    fun speechRange(samples: FloatArray, sampleRate: Int = 16_000, threshold: Float = 0.008f): IntRange? {
        val frame = sampleRate / 50
        if (samples.size < frame) return null
        var first = -1
        var last = 0
        var i = 0
        while (i + frame <= samples.size) {
            if (rms(samples, i, i + frame) >= threshold) {
                if (first < 0) first = i
                last = i + frame
            }
            i += frame
        }
        if (first < 0) return null
        val start = maxOf(0, first - (0.15 * sampleRate).toInt())
        val end = minOf(samples.size, last + (0.25 * sampleRate).toInt())
        return start until end
    }
}
