package app.evoo.android

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Reads a 16-bit PCM, 16 kHz, mono WAV file (what `say --data-format=LEI16@16000` writes) as floats. */
object Wav {
    fun read(file: File): FloatArray {
        val bytes = file.readBytes()
        require(bytes.size > 44 && String(bytes, 0, 4) == "RIFF" && String(bytes, 8, 4) == "WAVE") { "Not a WAV file" }
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        var at = 12
        while (at + 8 <= bytes.size) { // walk the chunks to "data"
            val id = String(bytes, at, 4)
            val size = buffer.getInt(at + 4)
            if (id == "data") {
                val n = minOf(size, bytes.size - at - 8) / 2
                return FloatArray(n) { buffer.getShort(at + 8 + it * 2) / 32768f }
            }
            at += 8 + size + (size and 1)
        }
        throw IllegalArgumentException("No audio in the WAV file")
    }
}
