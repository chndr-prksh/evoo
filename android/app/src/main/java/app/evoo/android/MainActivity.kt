package app.evoo.android

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import app.evoo.core.EvooPipeline
import com.google.mlkit.genai.common.FeatureStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

/** Setup in three steps (microphone, speech model, keyboard) and a box to try dictation without leaving the app. */
class MainActivity : AppCompatActivity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var dictation: Dictation
    private val tick = object : Runnable {
        override fun run() {
            refresh()
            handler.postDelayed(this, 500)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.main)
        dictation = Dictation(this, scope, ::showTry, ::insertTry)

        find<Button>(R.id.mic_button).setOnClickListener {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), 1)
        }
        find<Button>(R.id.model_button).setOnClickListener { Models.speech.download(this) }
        find<Button>(R.id.keyboard_enable).setOnClickListener {
            startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
        }
        find<Button>(R.id.keyboard_switch).setOnClickListener { imm().showInputMethodPicker() }
        find<Button>(R.id.try_button).setOnClickListener { dictation.toggle() }

        find<Button>(R.id.polish_button).setOnClickListener {
            if (Polish.Google.status == FeatureStatus.DOWNLOADABLE) Polish.Google.download(this) else Models.polish.download(this)
            Polish.setEnabled(this, true)
        }
        find<Button>(R.id.polish_toggle).setOnClickListener { Polish.setEnabled(this, !Polish.isEnabled(this)) }
        find<Button>(R.id.update_button).setOnClickListener {
            (Updater.state as? Updater.State.Available)?.let { Updater.install(this, it.release) }
        }
        find<TextView>(R.id.version).setOnClickListener { Updater.check(force = true) }
        Polish.warmUp(this) // also asks the phone whether it has Google's built-in AI
        runTestClip(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        runTestClip(intent)
    }

    /**
     * For automated tests (adb): `--es evoo_test_wav name.wav` runs a 16 kHz mono WAV from this app's own
     * files/test folder through the exact dictation path (speech → rules → polish) and writes the text to
     * files/test/result.txt and the Try box.
     */
    private fun runTestClip(intent: Intent?) {
        val name = intent?.getStringExtra("evoo_test_wav") ?: return
        val dir = getExternalFilesDir("test") ?: return
        val file = java.io.File(dir, java.io.File(name).name) // never outside our own folder
        val result = java.io.File(dir, "result.txt").apply { delete() }
        Thread {
            val text = runCatching {
                val samples = Wav.read(file)
                if (intent.getBooleanExtra("evoo_wait_polish", false)) {
                    Polish.Google.refresh(this)
                    if (Polish.engine(this) == Polish.Engine.QWEN) Polish.Qwen.warmUp(this)
                }
                val started = System.currentTimeMillis()
                val out = Dictation.transcribe(this, samples)
                android.util.Log.i("EvooTest", "${file.name}: ${System.currentTimeMillis() - started} ms, engine ${Polish.engine(this)} → $out")
                out
            }.getOrElse { "ERROR: ${it.message}" }
            result.writeText(text)
            runOnUiThread { find<EditText>(R.id.try_box).setText(text) }
        }.start()
    }

    override fun onResume() {
        super.onResume()
        handler.post(tick)
        Updater.check()
    }

    override fun onPause() {
        handler.removeCallbacks(tick)
        if (dictation.isListening) dictation.cancel()
        super.onPause()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    /** Brings the three setup cards up to date. */
    private fun refresh() {
        val micOk = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        find<TextView>(R.id.mic_title).text = done("1 · Microphone", micOk)
        find<Button>(R.id.mic_button).visibility = if (micOk) View.GONE else View.VISIBLE

        val progress = find<ProgressBar>(R.id.model_progress)
        val button = find<Button>(R.id.model_button)
        val body = find<TextView>(R.id.model_body)
        when (val state = Models.speech.state(this)) {
            ModelSet.State.Ready -> {
                find<TextView>(R.id.model_title).text = done("2 · Speech model", true)
                body.text = "Downloaded. Evoo now works offline."
                progress.visibility = View.GONE
                button.visibility = View.GONE
            }
            is ModelSet.State.Downloading -> {
                body.text = "Downloading… ${(state.fraction * 100).toInt()}% of 670 MB. You can leave this screen; it continues in the background."
                progress.visibility = View.VISIBLE
                progress.isIndeterminate = false
                progress.progress = (state.fraction * 1000).toInt()
                button.visibility = View.GONE
            }
            ModelSet.State.Verifying -> {
                body.text = "Checking the download…"
                progress.visibility = View.VISIBLE
                progress.isIndeterminate = true
                button.visibility = View.GONE
            }
            is ModelSet.State.Failed -> {
                body.text = state.reason
                progress.visibility = View.GONE
                button.visibility = View.VISIBLE
                button.text = "Try again"
            }
            ModelSet.State.Missing -> {
                progress.visibility = View.GONE
                button.visibility = View.VISIBLE
            }
        }

        refreshPolish()
        refreshUpdate()

        val enabled = imm().enabledInputMethodList.any { it.packageName == packageName }
        val selected = Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)?.startsWith("$packageName/") == true
        find<TextView>(R.id.keyboard_title).text = done("3 · Evoo keyboard", enabled)
        find<Button>(R.id.keyboard_enable).visibility = if (enabled) View.GONE else View.VISIBLE
        find<Button>(R.id.keyboard_switch).visibility = if (enabled) View.VISIBLE else View.GONE
        find<Button>(R.id.keyboard_switch).text = if (selected) "Evoo keyboard is active" else "Switch keyboard"
    }

    private fun refreshPolish() {
        val title = find<TextView>(R.id.polish_title)
        val body = find<TextView>(R.id.polish_body)
        val progress = find<ProgressBar>(R.id.polish_progress)
        val button = find<Button>(R.id.polish_button)
        val toggle = find<Button>(R.id.polish_toggle)
        val google = Polish.Google.status
        val qwen = Models.polish.state(this)
        val ready = google == FeatureStatus.AVAILABLE || qwen == ModelSet.State.Ready
        val on = Polish.isEnabled(this)
        title.text = done("4 · AI polish", ready && on) + if (ready && !on) "  (off)" else ""
        body.text = Polish.describe(this)
        progress.visibility = View.GONE
        button.visibility = if (ready) View.GONE else View.VISIBLE
        toggle.visibility = if (ready) View.VISIBLE else View.GONE
        toggle.text = if (on) "Turn off" else "Turn on"
        if (ready) return
        when {
            google == FeatureStatus.DOWNLOADING || Polish.Google.downloading -> {
                body.text = "Fetching Google's on-device AI model… this continues in the background."
                progress.visibility = View.VISIBLE
                progress.isIndeterminate = true
                button.visibility = View.GONE
            }
            google == FeatureStatus.DOWNLOADABLE -> button.text = "Turn on"
            qwen is ModelSet.State.Downloading -> {
                body.text = "Downloading… ${(qwen.fraction * 100).toInt()}% of ${Models.polish.megabytes} MB."
                progress.visibility = View.VISIBLE
                progress.isIndeterminate = false
                progress.progress = (qwen.fraction * 1000).toInt()
                button.visibility = View.GONE
            }
            qwen == ModelSet.State.Verifying -> {
                body.text = "Checking the download…"
                progress.visibility = View.VISIBLE
                progress.isIndeterminate = true
                button.visibility = View.GONE
            }
            qwen is ModelSet.State.Failed -> { body.text = qwen.reason; button.text = "Try again" }
            else -> button.text = "Download (${Models.polish.megabytes} MB)"
        }
    }

    private fun refreshUpdate() {
        val card = find<View>(R.id.update_card)
        val body = find<TextView>(R.id.update_body)
        val progress = find<ProgressBar>(R.id.update_progress)
        val button = find<Button>(R.id.update_button)
        find<TextView>(R.id.version).text = "Evoo ${BuildConfig.VERSION_NAME} · Check for updates"
        when (val state = Updater.state) {
            Updater.State.Idle -> card.visibility = View.GONE
            is Updater.State.Available -> {
                card.visibility = View.VISIBLE
                body.text = "Build ${state.release.build} is ready (you have ${BuildConfig.VERSION_CODE}). Your settings and models are kept."
                progress.visibility = View.GONE
                button.visibility = View.VISIBLE
            }
            is Updater.State.Downloading -> {
                card.visibility = View.VISIBLE
                body.text = "Downloading the update… ${(state.fraction * 100).toInt()}%"
                progress.visibility = View.VISIBLE
                progress.progress = (state.fraction * 1000).toInt()
                button.visibility = View.GONE
            }
            is Updater.State.Failed -> {
                card.visibility = View.VISIBLE
                body.text = state.reason
                progress.visibility = View.GONE
                button.visibility = View.GONE
            }
        }
    }

    private fun done(title: String, ok: Boolean) = if (ok) "$title  ✓" else title

    private fun showTry(state: Dictation.State) {
        val button = find<Button>(R.id.try_button)
        val status = find<TextView>(R.id.try_status)
        when (state) {
            Dictation.State.Idle -> { button.text = "🎤  Tap to dictate"; status.text = "Tap the mic and speak." }
            Dictation.State.Listening -> { button.text = "■  Listening… tap when you're done"; status.text = "Listening…" }
            Dictation.State.Thinking -> { button.text = "Writing…"; status.text = "Writing…" }
            Dictation.State.Polishing -> { button.text = "Polishing…"; status.text = "Polishing…" }
            is Dictation.State.Note -> { button.text = "🎤  Tap to dictate"; status.text = state.message.replace("Open the Evoo app to", "First,") }
        }
        button.isEnabled = state != Dictation.State.Thinking && state != Dictation.State.Polishing
    }

    private fun insertTry(text: String) {
        val box = find<EditText>(R.id.try_box)
        val at = box.selectionStart.coerceAtLeast(0)
        val before = if (at > 0) box.text[at - 1] else null
        box.text.insert(at, EvooPipeline.spaced(text, before))
    }

    private fun imm() = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager

    private fun <T : View> find(id: Int): T = findViewById(id)
}
