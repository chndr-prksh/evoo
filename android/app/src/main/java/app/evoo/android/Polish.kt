package app.evoo.android

import android.content.Context
import android.os.Build
import android.util.Log
import app.evoo.core.RefinePrompt
import com.google.mlkit.genai.common.DownloadCallback
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.proofreading.Proofreader
import com.google.mlkit.genai.proofreading.ProofreaderOptions
import com.google.mlkit.genai.proofreading.Proofreading
import com.google.mlkit.genai.proofreading.ProofreadingRequest
import java.util.concurrent.TimeUnit

/** The bridge to llama.cpp (src/main/cpp/evoo_llama.cpp). */
object LlamaNative {
    init { System.loadLibrary("evoollama") }
    external fun load(path: ByteArray, threads: Int): Long
    external fun complete(handle: Long, prefix: ByteArray, suffix: ByteArray, maxTokens: Int, statePath: ByteArray): ByteArray?
    external fun free(handle: Long)
}

/**
 * AI polish, on the phone. Two engines, picked per phone:
 *  • Google's built-in on-device AI (Gemini Nano, through ML Kit's proofreading for voice input) on recent phones
 *    that have it — nothing for Evoo to download.
 *  • Qwen3 0.6B on llama.cpp everywhere else — the Mac app's small polish model, a one-time 400 MB download.
 * Either way the text never leaves the phone. Polish runs after Evoo's rules, only on text with something to fix,
 * and its answer is checked before it replaces the rules' text.
 */
object Polish {
    enum class Engine { GOOGLE, QWEN, NONE }

    private const val TAG = "EvooPolish"
    private const val PREFS = "polish"

    fun isEnabled(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("enabled", true)
    fun setEnabled(context: Context, on: Boolean) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("enabled", on).apply()

    /** The engine that would polish right now. Cheap: uses the last known Google status. */
    fun engine(context: Context): Engine = when {
        !isEnabled(context) -> Engine.NONE
        Google.status == FeatureStatus.AVAILABLE -> Engine.GOOGLE
        Models.polish.isReady(context) -> Engine.QWEN
        else -> Engine.NONE
    }

    /** Gets the engine ready in the background (model in memory, instructions read) so the first polish is quick. */
    fun warmUp(context: Context) {
        Thread {
            Google.refresh(context)
            if (engine(context) == Engine.QWEN) runCatching { Qwen.warmUp(context) }
        }.start()
    }

    /**
     * The polished text, or `text` unchanged when there's nothing to fix, no engine is ready yet, the model takes
     * too long, or its answer doesn't pass the checks. Call from a background thread.
     */
    fun run(context: Context, text: String): String {
        if (!RefinePrompt.needsPolish(text)) return text
        val started = System.currentTimeMillis()
        val (engine, answer) = when (engine(context)) {
            Engine.GOOGLE -> "google" to runCatching { Google.proofread(context, text) }.getOrNull()
            Engine.QWEN -> "qwen" to runCatching { Qwen.polish(context, text) }.getOrNull()
            Engine.NONE -> return text
        }
        val accepted = answer?.let { RefinePrompt.accept(it, text) }
        Log.i(TAG, "$engine polish ${System.currentTimeMillis() - started} ms, ${if (accepted != null) "used" else "kept the rules' text"}")
        return accepted ?: text
    }

    fun unload() = Qwen.unload()

    /** Google's on-device AI, where the phone has it. */
    object Google {
        /** A FeatureStatus value; UNAVAILABLE until `refresh` has asked the phone. */
        @Volatile var status: Int = FeatureStatus.UNAVAILABLE
            private set
        @Volatile var downloading = false
            private set
        private var client: Proofreader? = null

        private fun client(context: Context): Proofreader = client ?: Proofreading.getClient(
            ProofreaderOptions.builder(context.applicationContext)
                .setInputType(ProofreaderOptions.InputType.VOICE)
                .setLanguage(ProofreaderOptions.Language.ENGLISH)
                .build()
        ).also { client = it }

        /** Asks the phone whether its built-in AI can proofread. Blocking; safe on any phone. */
        @Synchronized fun refresh(context: Context): Int {
            status = try {
                client(context).checkFeatureStatus().get(5, TimeUnit.SECONDS)
            } catch (e: Throwable) {
                Log.i(TAG, "Google on-device AI not available: ${e.message}")
                FeatureStatus.UNAVAILABLE
            }
            if (status == FeatureStatus.DOWNLOADING) downloading = true
            if (status == FeatureStatus.AVAILABLE) downloading = false
            return status
        }

        /** The phone has the feature but not its model yet: ask Google's AI service to fetch it. */
        fun download(context: Context) {
            downloading = true
            try {
                client(context).downloadFeature(object : DownloadCallback {
                    override fun onDownloadStarted(bytesToDownload: Long) {}
                    override fun onDownloadProgress(totalBytesDownloaded: Long) {}
                    override fun onDownloadCompleted() { downloading = false; status = FeatureStatus.AVAILABLE }
                    override fun onDownloadFailed(e: GenAiException) { downloading = false; Log.w(TAG, "download failed: ${e.message}") }
                })
            } catch (e: Throwable) {
                downloading = false
            }
        }

        fun proofread(context: Context, text: String): String? {
            // The built-in model takes short inputs (under 256 tokens): go sentence by sentence when needed.
            val parts = if (text.length <= 500) listOf(text) else text.split(Regex("(?<=[.!?])\\s+"))
            return parts.joinToString(" ") { part ->
                if (part.split(' ').size < 4) part
                else client(context).runInference(ProofreadingRequest.builder(part).build())
                    .get(4, TimeUnit.SECONDS).results.firstOrNull()?.text ?: part
            }
        }
    }

    /** Qwen3 0.6B on llama.cpp. */
    object Qwen {
        private var handle = 0L
        private val lock = Any()
        @Volatile var isWarm = false
            private set

        private fun load(context: Context) {
            if (handle != 0L) return
            val file = Models.polish.file(context, Models.polish.files[0].name)
            val threads = Runtime.getRuntime().availableProcessors().coerceIn(2, 4)
            handle = LlamaNative.load(file.absolutePath.toByteArray(), threads)
            check(handle != 0L) { "Couldn't load the polish model" }
        }

        /** Where the model's "I've read the instructions" state is kept, named after the exact instructions and model. */
        private fun statePath(context: Context): ByteArray {
            val name = "polish-${RefinePrompt.prefix.hashCode().toUInt()}-${Models.polish.files[0].sha256.take(8)}.state"
            val dir = java.io.File(context.filesDir, "polish-state").apply { mkdirs() }
            dir.listFiles()?.filter { it.name != name }?.forEach { it.delete() } // older instructions or model
            return java.io.File(dir, name).absolutePath.toByteArray()
        }

        /** Loads the model and has it read the instructions once (slow the very first time; after that the result is restored from disk). */
        fun warmUp(context: Context) {
            synchronized(lock) {
                if (isWarm) return
                val started = System.currentTimeMillis()
                load(context)
                LlamaNative.complete(handle, RefinePrompt.prefix.toByteArray(), ByteArray(0), 0, statePath(context))
                isWarm = true
                Log.i(TAG, "qwen ready in ${System.currentTimeMillis() - started} ms")
            }
        }

        fun polish(context: Context, text: String): String? {
            // Not ready yet: don't make the person wait for it — this dictation goes in with the rules' text.
            if (!isWarm) { Thread { runCatching { warmUp(context) } }.start(); return null }
            return synchronized(lock) {
                val words = text.split(' ').count { it.isNotEmpty() }
                LlamaNative.complete(handle, RefinePrompt.prefix.toByteArray(), RefinePrompt.suffix(text).toByteArray(),
                    RefinePrompt.maxTokens(words), statePath(context))?.toString(Charsets.UTF_8)
            }
        }

        fun unload() {
            synchronized(lock) {
                if (handle != 0L) LlamaNative.free(handle)
                handle = 0L
                isWarm = false
            }
        }
    }

    /** A plain-words description of this phone's polish, for the setup screen. */
    fun describe(context: Context): String = when {
        Google.status == FeatureStatus.AVAILABLE -> "Using the AI built into this ${Build.MODEL} (Google's on-device model). Nothing to download."
        Google.status == FeatureStatus.DOWNLOADABLE || Google.status == FeatureStatus.DOWNLOADING || Google.downloading ->
            "This ${Build.MODEL} has Google's on-device AI. It needs to fetch its model once."
        Models.polish.isReady(context) -> "Using Evoo's small on-device model (Qwen3 0.6B)."
        else -> "Tidies grammar, leftover fillers and misheard words, on the phone. This phone doesn't have Google's built-in AI, so Evoo uses its own small model: a one-time ${Models.polish.megabytes} MB download."
    }
}
