package app.evoo.android

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import java.io.File
import java.security.MessageDigest

/**
 * A model Evoo downloads once: fetched by Android's own download manager (it keeps going in the background and
 * resumes after a dropped connection), then checked against pinned SHA-256s before it is ever loaded.
 */
class ModelSet(
    private val id: String,
    private val folder: String,
    private val base: String,
    private val revision: String,
    private val notificationTitle: String,
    val files: List<ModelFile>,
) {
    class ModelFile(val name: String, val size: Long, val sha256: String)

    val totalBytes = files.sumOf { it.size }
    val megabytes: Int get() = (totalBytes / 1_000_000).toInt()

    sealed class State {
        object Missing : State()
        class Downloading(val fraction: Float) : State()
        object Verifying : State()
        object Ready : State()
        class Failed(val reason: String) : State()
    }

    fun dir(context: Context): File? = context.getExternalFilesDir(folder)

    fun file(context: Context, name: String): File = File(dir(context), name)

    private fun marker(context: Context) = File(dir(context), ".verified-$revision")

    fun isReady(context: Context): Boolean {
        dir(context) ?: return false
        return marker(context).exists() && files.all { file(context, it.name).length() == it.size }
    }

    private fun prefs(context: Context) = context.getSharedPreferences("model-$id", Context.MODE_PRIVATE)

    @Volatile private var verifying = false
    @Volatile private var failure: String? = null

    /** Starts (or continues) the download of whatever is missing. */
    fun download(context: Context) {
        val dir = dir(context) ?: run { failure = "No storage available for the model"; return }
        failure = null
        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val ids = mutableSetOf<String>()
        for (f in files) {
            if (File(dir, f.name).length() == f.size) continue
            File(dir, f.name).delete()
            File(dir, f.name + ".part").delete()
            val request = DownloadManager.Request(Uri.parse(base + f.name))
                .setTitle(notificationTitle)
                .setDescription(f.name)
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
                .setAllowedOverMetered(true)
                .setDestinationInExternalFilesDir(context, folder, f.name + ".part")
            ids.add(manager.enqueue(request).toString())
        }
        prefs(context).edit().putStringSet("ids", ids).apply()
        if (ids.isEmpty()) verify(context)
    }

    /** Where things stand. Cheap; the setup screen calls it twice a second. */
    fun state(context: Context): State {
        if (isReady(context)) return State.Ready
        failure?.let { return State.Failed(it) }
        if (verifying) return State.Verifying
        val ids = prefs(context).getStringSet("ids", emptySet())!!.mapNotNull { it.toLongOrNull() }
        if (ids.isEmpty()) return State.Missing
        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        var done = files.filter { file(context, it.name).length() == it.size }.sumOf { it.size }
        var running = 0
        var failed: String? = null
        manager.query(DownloadManager.Query().setFilterById(*ids.toLongArray()))?.use { c ->
            val status = c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
            val soFar = c.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
            val reason = c.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON)
            while (c.moveToNext()) {
                when (c.getInt(status)) {
                    DownloadManager.STATUS_FAILED -> failed = "Download failed (code ${c.getInt(reason)}). Check the connection and try again."
                    DownloadManager.STATUS_SUCCESSFUL -> {}
                    else -> { running += 1; done += maxOf(0L, c.getLong(soFar)) }
                }
            }
        }
        failed?.let {
            prefs(context).edit().remove("ids").apply()
            return State.Failed(it)
        }
        if (running == 0) {
            verify(context)
            return State.Verifying
        }
        // Finished parts are still named ".part" until everything is verified.
        done += files.filter { File(dir(context), it.name + ".part").length() == it.size }.sumOf { it.size }
        return State.Downloading((done.toDouble() / totalBytes).toFloat().coerceIn(0f, 0.99f))
    }

    /** Checks every file against its pinned SHA-256, then marks the model usable. */
    private fun verify(context: Context) {
        if (verifying) return
        verifying = true
        Thread {
            try {
                val dir = dir(context)!!
                for (f in files) {
                    val final = File(dir, f.name)
                    val part = File(dir, f.name + ".part")
                    if (final.length() != f.size) {
                        if (part.length() != f.size) throw IllegalStateException("${f.name} is incomplete — tap Download again")
                        if (sha256(part) != f.sha256) {
                            part.delete()
                            throw IllegalStateException("${f.name} didn't verify — tap Download again")
                        }
                        if (!part.renameTo(final)) throw IllegalStateException("Couldn't save ${f.name}")
                    }
                }
                marker(context).writeText("ok")
                prefs(context).edit().remove("ids").apply()
            } catch (e: Exception) {
                failure = e.message ?: "The model didn't verify"
                prefs(context).edit().remove("ids").apply()
            } finally {
                verifying = false
            }
        }.start()
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(1 shl 20)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                digest.update(buffer, 0, n)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}

/**
 * Evoo's models. Speech: NVIDIA Parakeet TDT 0.6B v3 (CC-BY-4.0), the model the Mac app uses, in the 8-bit ONNX
 * build the sherpa-onnx project made for phones. Polish: Qwen3 0.6B (Apache-2.0), the Mac app's small polish model,
 * in a 4-bit build that fits a phone.
 */
object Models {
    val speech = ModelSet(
        id = "speech", folder = "models/parakeet-v3-int8", revision = "2bda32ec70b097a55adaa07d9a7173915b43cc78",
        base = "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/2bda32ec70b097a55adaa07d9a7173915b43cc78/",
        notificationTitle = "Evoo speech model",
        files = listOf(
            ModelSet.ModelFile("encoder.int8.onnx", 652_184_281, "acfc2b4456377e15d04f0243af540b7fe7c992f8d898d751cf134c3a55fd2247"),
            ModelSet.ModelFile("decoder.int8.onnx", 11_845_275, "179e50c43d1a9de79c8a24149a2f9bac6eb5981823f2a2ed88d655b24248db4e"),
            ModelSet.ModelFile("joiner.int8.onnx", 6_355_277, "3164c13fc2821009440d20fcb5fdc78bff28b4db2f8d0f0b329101719c0948b3"),
            ModelSet.ModelFile("tokens.txt", 93_939, "d58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d"),
        ),
    )
    val polish = ModelSet(
        id = "polish", folder = "models/qwen3-0.6b-q4", revision = "50968a4468ef4233ed78cd7c3de230dd1d61a56b",
        base = "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/50968a4468ef4233ed78cd7c3de230dd1d61a56b/",
        notificationTitle = "Evoo polish model",
        files = listOf(
            ModelSet.ModelFile("Qwen3-0.6B-Q4_K_M.gguf", 396_705_472, "ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a"),
        ),
    )
}
