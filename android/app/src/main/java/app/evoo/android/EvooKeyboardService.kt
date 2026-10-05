package app.evoo.android

import android.content.Context
import android.content.Intent
import android.inputmethodservice.InputMethodService
import android.os.Build
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.ImageView
import android.widget.TextView
import app.evoo.core.EvooPipeline
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

/**
 * The Evoo keyboard: a big mic instead of letters. Tap, speak, tap — the text goes in at the cursor, in any app.
 * Android lets a keyboard use the microphone while it is on screen, so everything happens right here.
 */
class EvooKeyboardService : InputMethodService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var status: TextView? = null
    private var mic: ImageView? = null
    private lateinit var dictation: Dictation
    /** How many characters the last dictation inserted, for the undo key. */
    private var lastInserted = 0

    override fun onCreate() {
        super.onCreate()
        dictation = Dictation(this, scope, ::show, ::insert)
    }

    override fun onCreateInputView(): View {
        val view = layoutInflater.inflate(R.layout.keyboard, null)
        status = view.findViewById(R.id.status)
        mic = view.findViewById(R.id.mic)
        mic?.setOnClickListener { dictation.toggle() }
        view.findViewById<View>(R.id.switch_keyboard).apply {
            setOnClickListener { switchAway() }
            setOnLongClickListener { imm().showInputMethodPicker(); true }
        }
        view.findViewById<View>(R.id.undo).setOnClickListener { undo() }
        view.findViewById<View>(R.id.backspace).apply {
            setOnClickListener { backspace() }
            setOnLongClickListener { deleteWord(); true }
        }
        view.findViewById<View>(R.id.enter).setOnClickListener { enter() }
        view.findViewById<View>(R.id.space).setOnClickListener { type(" ") }
        for ((id, text) in listOf(R.id.comma to ",", R.id.period to ".", R.id.question to "?", R.id.exclaim to "!", R.id.at to "@")) {
            view.findViewById<View>(id).setOnClickListener { type(text) }
        }
        return view
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        lastInserted = 0
        show(dictation.blocker()?.let { Dictation.State.Note(it) } ?: Dictation.State.Idle)
        if (dictation.blocker() == null) Polish.warmUp(this) // ready by the time you finish speaking
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        if (dictation.isListening) dictation.cancel() // the mic never stays on once the keyboard is gone
        super.onFinishInputView(finishingInput)
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        // Android is short of memory and the keyboard isn't in use: give back the model's ~700 MB.
        if (level >= TRIM_MEMORY_BACKGROUND && !dictation.isListening) { SpeechEngine.unload(); Polish.unload() }
    }

    override fun onDestroy() {
        if (dictation.isListening) dictation.cancel()
        scope.cancel()
        super.onDestroy()
    }

    private fun show(state: Dictation.State) {
        val (text, live) = when (state) {
            Dictation.State.Idle -> "Tap the mic and speak" to false
            Dictation.State.Listening -> "Listening… tap again when you're done" to true
            Dictation.State.Thinking -> "Writing…" to false
            Dictation.State.Polishing -> "Polishing…" to false
            is Dictation.State.Note -> state.message to false
        }
        status?.text = text
        mic?.setBackgroundResource(if (live) R.drawable.mic_live else R.drawable.mic_idle)
        mic?.alpha = if (state == Dictation.State.Thinking || state == Dictation.State.Polishing) 0.5f else 1f
        // Without the microphone or the model, a tap on the note opens the app to finish setup.
        status?.setOnClickListener(if (state is Dictation.State.Note && dictation.blocker() != null) View.OnClickListener { openApp() } else null)
    }

    private fun insert(text: String) {
        val ic = currentInputConnection ?: return
        val before = ic.getTextBeforeCursor(1, 0)?.lastOrNull()
        val spaced = EvooPipeline.spaced(text, before)
        ic.commitText(spaced, 1)
        lastInserted = spaced.length
    }

    private fun type(text: String) {
        currentInputConnection?.commitText(text, 1)
        lastInserted = 0
    }

    private fun undo() {
        if (lastInserted <= 0) return
        currentInputConnection?.deleteSurroundingText(lastInserted, 0)
        lastInserted = 0
    }

    private fun backspace() {
        val ic = currentInputConnection ?: return
        if (!ic.getSelectedText(0).isNullOrEmpty()) ic.commitText("", 1) else ic.deleteSurroundingText(1, 0)
        lastInserted = 0
    }

    private fun deleteWord() {
        val ic = currentInputConnection ?: return
        val before = ic.getTextBeforeCursor(60, 0)?.toString() ?: return
        val trimmed = before.trimEnd()
        val cut = before.length - (trimmed.lastIndexOf(' ') + 1)
        ic.deleteSurroundingText(maxOf(1, cut), 0)
        lastInserted = 0
    }

    private fun enter() {
        val info = currentInputEditorInfo
        val action = (info?.imeOptions ?: 0) and EditorInfo.IME_MASK_ACTION
        val noAction = info == null || (info.imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION) != 0 ||
            action == EditorInfo.IME_ACTION_NONE || action == EditorInfo.IME_ACTION_UNSPECIFIED
        if (noAction) sendDownUpKeyEvents(KeyEvent.KEYCODE_ENTER) else currentInputConnection?.performEditorAction(action)
        lastInserted = 0
    }

    private fun switchAway() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            if (!switchToPreviousInputMethod()) imm().showInputMethodPicker()
        } else {
            imm().showInputMethodPicker()
        }
    }

    private fun openApp() {
        startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun imm() = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
}
