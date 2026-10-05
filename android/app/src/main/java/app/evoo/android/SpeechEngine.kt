package app.evoo.android

import android.content.Context
import app.evoo.core.AudioStats
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig
import com.k2fsa.sherpa.onnx.OfflineTransducerModelConfig

/**
 * Parakeet TDT 0.6B v3 running on the phone through sherpa-onnx. Nothing leaves the device: the audio goes from
 * the microphone to this model in memory and is thrown away once the text is out.
 */
object SpeechEngine {
    private var recognizer: OfflineRecognizer? = null
    private val lock = Any()

    val isLoaded: Boolean get() = recognizer != null

    /** Loads the model (a few seconds the first time; it then stays in memory until Android needs the space). */
    fun load(context: Context) {
        synchronized(lock) {
            if (recognizer != null) return
            check(ModelStore.isReady(context)) { "The speech model isn't downloaded yet" }
            val threads = Runtime.getRuntime().availableProcessors().coerceIn(2, 4)
            val config = OfflineRecognizerConfig(
                featConfig = FeatureConfig(sampleRate = 16000, featureDim = 80),
                modelConfig = OfflineModelConfig(
                    transducer = OfflineTransducerModelConfig(
                        encoder = ModelStore.file(context, "encoder.int8.onnx").absolutePath,
                        decoder = ModelStore.file(context, "decoder.int8.onnx").absolutePath,
                        joiner = ModelStore.file(context, "joiner.int8.onnx").absolutePath,
                    ),
                    tokens = ModelStore.file(context, "tokens.txt").absolutePath,
                    numThreads = threads,
                    provider = "cpu",
                    modelType = "nemo_transducer",
                ),
            )
            recognizer = OfflineRecognizer(config = config)
        }
    }

    fun unload() {
        synchronized(lock) {
            recognizer?.release()
            recognizer = null
        }
    }

    /** Speech → text. Long recordings are cut at quiet moments so each piece stays small. */
    fun transcribe(samples: FloatArray): String {
        val speech = AudioStats.speechRange(samples) ?: return ""
        val clip = samples.copyOfRange(speech.first, speech.last + 1)
        return pieces(clip).joinToString(" ") { piece ->
            synchronized(lock) {
                val r = recognizer ?: error("The speech model isn't loaded")
                val stream = r.createStream()
                try {
                    stream.acceptWaveform(piece, 16000)
                    r.decode(stream)
                    r.getResult(stream).text.trim()
                } finally {
                    stream.release()
                }
            }
        }.trim()
    }

    /** Pieces of at most ~30 s, cut at the quietest 100 ms of each piece's last 5 s. */
    private fun pieces(clip: FloatArray, rate: Int = 16000): List<FloatArray> {
        val max = 30 * rate
        if (clip.size <= max) return listOf(clip)
        val out = ArrayList<FloatArray>()
        var start = 0
        while (clip.size - start > max) {
            val windowStart = start + max - 5 * rate
            var best = start + max
            var bestEnergy = Double.MAX_VALUE
            var i = windowStart
            while (i + rate / 10 <= start + max) {
                var e = 0.0
                for (k in i until i + rate / 10) e += clip[k] * clip[k]
                if (e < bestEnergy) { bestEnergy = e; best = i + rate / 20 }
                i += rate / 20
            }
            out.add(clip.copyOfRange(start, best))
            start = best
        }
        out.add(clip.copyOfRange(start, clip.size))
        return out
    }
}
