package app.evoo.android

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import app.evoo.core.AudioStats
import app.evoo.core.EvooPipeline
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * One dictation: tap → record → tap → speech model → Evoo's rules → text. Used by the keyboard and by the
 * "try it" box in the app, so both behave the same.
 */
class Dictation(
    private val context: Context,
    private val scope: CoroutineScope,
    private val onState: (State) -> Unit,
    private val onText: (String) -> Unit,
) {
    sealed class State {
        object Idle : State()
        object Listening : State()
        object Thinking : State()
        /** Something the person should know ("Didn't catch that"); goes back to idle on the next tap. */
        class Note(val message: String) : State()
    }

    private val recorder = Recorder()
    private var busy = false

    val isListening: Boolean get() = recorder.isRecording

    /** What's missing before dictation can work, or null when everything is in place. */
    fun blocker(): String? = when {
        ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED ->
            "Open the Evoo app to allow the microphone"
        !ModelStore.isReady(context) -> "Open the Evoo app to download the speech model"
        else -> null
    }

    /** Tap the mic: start listening, or finish and type what was said. */
    fun toggle() {
        if (busy) return
        if (recorder.isRecording) return finish()
        blocker()?.let { return onState(State.Note(it)) }
        if (!recorder.start()) return onState(State.Note("Couldn't start the microphone"))
        onState(State.Listening)
        // Load the model while the person is still talking.
        if (!SpeechEngine.isLoaded) scope.launch(Dispatchers.Default) { runCatching { SpeechEngine.load(context) } }
    }

    /** Stop without typing anything. */
    fun cancel() {
        if (recorder.isRecording) recorder.stop()
        onState(State.Idle)
    }

    private fun finish() {
        val samples = recorder.stop()
        if (AudioStats.hasNoSpeech(samples)) return onState(State.Note("Didn't catch that — tap and speak"))
        busy = true
        onState(State.Thinking)
        scope.launch {
            val result = withContext(Dispatchers.Default) {
                runCatching {
                    SpeechEngine.load(context)
                    EvooPipeline.process(SpeechEngine.transcribe(samples)).text
                }
            }
            busy = false
            result.onSuccess { text ->
                if (text.isEmpty()) onState(State.Note("Didn't catch that — tap and speak"))
                else { onText(text); onState(State.Idle) }
            }.onFailure { onState(State.Note(it.message ?: "Something went wrong")) }
        }
    }
}
