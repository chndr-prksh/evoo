package app.evoo.android

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import kotlin.math.sqrt

/** Captures the microphone as 16 kHz mono floats — the format the speech model expects. Kept in memory only. */
class Recorder(private val onLevel: (Float) -> Unit = {}) {
    private var record: AudioRecord? = null
    private var thread: Thread? = null
    @Volatile private var running = false
    private val chunks = ArrayList<FloatArray>()

    val isRecording: Boolean get() = running

    /** Seconds recorded so far. */
    val seconds: Double get() = synchronized(chunks) { chunks.sumOf { it.size } } / SAMPLE_RATE.toDouble()

    /** Starts recording. The caller has already checked the microphone permission. */
    @SuppressLint("MissingPermission")
    fun start(): Boolean {
        if (running) return true
        val minBuffer = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (minBuffer <= 0) return false
        val r = try {
            AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT, maxOf(minBuffer, SAMPLE_RATE)) // ≥ 0.5 s of buffer
        } catch (e: Exception) { return false }
        if (r.state != AudioRecord.STATE_INITIALIZED) { r.release(); return false }
        synchronized(chunks) { chunks.clear() }
        record = r
        running = true
        r.startRecording()
        thread = Thread {
            val buffer = ShortArray(1600) // 0.1 s
            while (running) {
                val n = r.read(buffer, 0, buffer.size)
                if (n <= 0) continue
                val out = FloatArray(n)
                var sum = 0.0
                for (i in 0 until n) {
                    out[i] = buffer[i] / 32768f
                    sum += out[i] * out[i]
                }
                synchronized(chunks) { chunks.add(out) }
                onLevel(sqrt(sum / n).toFloat())
                if (seconds >= MAX_SECONDS) running = false
            }
        }.also { it.start() }
        return true
    }

    /** Stops and returns everything recorded. */
    fun stop(): FloatArray {
        running = false
        val r = record
        try { r?.stop() } catch (_: Exception) {} // unblocks the read in the thread
        thread?.join(1000)
        thread = null
        r?.release()
        record = null
        return synchronized(chunks) {
            val all = FloatArray(chunks.sumOf { it.size })
            var at = 0
            for (c in chunks) { c.copyInto(all, at); at += c.size }
            chunks.clear()
            all
        }
    }

    companion object {
        const val SAMPLE_RATE = 16_000
        /** One dictation is at most this long (the recording lives in memory). */
        const val MAX_SECONDS = 300
    }
}
