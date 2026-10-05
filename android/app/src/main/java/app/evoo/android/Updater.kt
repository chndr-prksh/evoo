package app.evoo.android

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * Updates without an app store: Evoo checks its GitHub release for a newer build, downloads the APK, checks its
 * SHA-256, and hands it to Android's installer (which asks you to confirm). Every build is signed with the same
 * key, so an update installs over the old version and keeps your settings and models.
 */
object Updater {
    private const val BASE = "https://github.com/chndr-prksh/evoo/releases/download/android/"

    class Release(val build: Int, val sha256: String, val size: Long)

    sealed class State {
        object Idle : State()
        class Available(val release: Release) : State()
        class Downloading(val fraction: Float) : State()
        class Failed(val reason: String) : State()
    }

    @Volatile var state: State = State.Idle
        private set
    @Volatile private var lastCheck = 0L

    /** Looks for a newer build (at most every few hours unless `force`). Runs in the background. */
    fun check(force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (state is State.Downloading || (!force && now - lastCheck < 6 * 3600_000L)) return
        lastCheck = now
        Thread {
            try {
                val json = JSONObject(open(BASE + "version.json").inputStream.bufferedReader().use { it.readText() })
                val release = Release(json.getInt("build"), json.getString("sha256"), json.getLong("size"))
                android.util.Log.i("EvooUpdate", "latest build ${release.build}, this is ${BuildConfig.VERSION_CODE}")
                state = if (release.build > BuildConfig.VERSION_CODE) State.Available(release) else State.Idle
            } catch (e: Exception) {
                android.util.Log.w("EvooUpdate", "check failed: $e")
                lastCheck = 0 // try again next time the app opens
                if (force) state = State.Failed("Couldn't check for updates: ${e.message ?: "no connection"}")
            }
        }.start()
    }

    /** Downloads the new build, verifies it, and opens Android's install prompt. */
    fun install(context: Context, release: Release) {
        if (state is State.Downloading) return
        state = State.Downloading(0f)
        val app = context.applicationContext
        Thread {
            try {
                val dir = File(app.cacheDir, "updates").apply { mkdirs() }
                val apk = File(dir, "Evoo-android.apk")
                val digest = MessageDigest.getInstance("SHA-256")
                open(BASE + "Evoo-android.apk").inputStream.use { input ->
                    apk.outputStream().use { output ->
                        val buffer = ByteArray(1 shl 16)
                        var done = 0L
                        while (true) {
                            val n = input.read(buffer)
                            if (n < 0) break
                            output.write(buffer, 0, n)
                            digest.update(buffer, 0, n)
                            done += n
                            state = State.Downloading((done.toFloat() / release.size).coerceIn(0f, 1f))
                        }
                    }
                }
                val sha = digest.digest().joinToString("") { "%02x".format(it) }
                if (sha != release.sha256) {
                    apk.delete()
                    throw IllegalStateException("The download didn't verify")
                }
                val uri = FileProvider.getUriForFile(app, "${app.packageName}.files", apk)
                app.startActivity(Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
                state = State.Available(release) // still pending until Android has installed it
            } catch (e: Exception) {
                android.util.Log.w("EvooUpdate", "install failed: $e")
                state = State.Failed("Update failed: ${e.message ?: "try again"}")
            }
        }.start()
    }

    private fun open(url: String): HttpURLConnection {
        val c = URL(url).openConnection() as HttpURLConnection
        c.instanceFollowRedirects = true
        c.connectTimeout = 15_000
        c.readTimeout = 30_000
        if (c.responseCode !in 200..299) throw IllegalStateException("HTTP ${c.responseCode}")
        return c
    }
}
