package app.evoo.core

/** What the speech model heard → what gets typed. The same order as the Mac app's DictationPipeline.postProcess. */
object EvooPipeline {
    data class Output(val text: String, val unresolved: Boolean)

    fun process(raw: String): Output {
        val cleaned = TextCleaner.clean(raw)
        if (cleaned.isEmpty()) return Output("", false)
        val result = DictationRules.apply(cleaned)
        // "i will", "i'm" → "I will", "I'm" (a speech-model slip).
        val text = result.text.replace(Regex("\\bi\\b(?=['’ ,]|$)"), "I")
        return Output(text, result.unresolved)
    }

    /** The text to insert, with a leading space when the cursor sits right after a word or punctuation. */
    fun spaced(text: String, before: Char?): String {
        if (text.isEmpty() || before == null) return text
        val needsSpace = !before.isWhitespace() && before !in "([{\"'“‘/-" && text.first() !in ".,;:!?)"
        return if (needsSpace) " $text" else text
    }
}
