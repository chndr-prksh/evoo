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
        find<Button>(R.id.model_button).setOnClickListener { ModelStore.download(this) }
        find<Button>(R.id.keyboard_enable).setOnClickListener {
            startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
        }
        find<Button>(R.id.keyboard_switch).setOnClickListener { imm().showInputMethodPicker() }
        find<Button>(R.id.try_button).setOnClickListener { dictation.toggle() }
    }

    override fun onResume() {
        super.onResume()
        handler.post(tick)
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
        when (val state = ModelStore.state(this)) {
            ModelStore.State.Ready -> {
                find<TextView>(R.id.model_title).text = done("2 · Speech model", true)
                body.text = "Downloaded. Evoo now works offline."
                progress.visibility = View.GONE
                button.visibility = View.GONE
            }
            is ModelStore.State.Downloading -> {
                body.text = "Downloading… ${(state.fraction * 100).toInt()}% of 670 MB. You can leave this screen; it continues in the background."
                progress.visibility = View.VISIBLE
                progress.isIndeterminate = false
                progress.progress = (state.fraction * 1000).toInt()
                button.visibility = View.GONE
            }
            ModelStore.State.Verifying -> {
                body.text = "Checking the download…"
                progress.visibility = View.VISIBLE
                progress.isIndeterminate = true
                button.visibility = View.GONE
            }
            is ModelStore.State.Failed -> {
                body.text = state.reason
                progress.visibility = View.GONE
                button.visibility = View.VISIBLE
                button.text = "Try again"
            }
            ModelStore.State.Missing -> {
                progress.visibility = View.GONE
                button.visibility = View.VISIBLE
            }
        }

        val enabled = imm().enabledInputMethodList.any { it.packageName == packageName }
        val selected = Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)?.startsWith("$packageName/") == true
        find<TextView>(R.id.keyboard_title).text = done("3 · Evoo keyboard", enabled)
        find<Button>(R.id.keyboard_enable).visibility = if (enabled) View.GONE else View.VISIBLE
        find<Button>(R.id.keyboard_switch).visibility = if (enabled) View.VISIBLE else View.GONE
        find<Button>(R.id.keyboard_switch).text = if (selected) "Evoo keyboard is active" else "Switch keyboard"
    }

    private fun done(title: String, ok: Boolean) = if (ok) "$title  ✓" else title

    private fun showTry(state: Dictation.State) {
        val button = find<Button>(R.id.try_button)
        val status = find<TextView>(R.id.try_status)
        when (state) {
            Dictation.State.Idle -> { button.text = "🎤  Tap to dictate"; status.text = "Tap the mic and speak." }
            Dictation.State.Listening -> { button.text = "■  Listening… tap when you're done"; status.text = "Listening…" }
            Dictation.State.Thinking -> { button.text = "Writing…"; status.text = "Writing…" }
            is Dictation.State.Note -> { button.text = "🎤  Tap to dictate"; status.text = state.message.replace("Open the Evoo app to", "First,") }
        }
        button.isEnabled = state != Dictation.State.Thinking
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
