package app.evoo.core

/**
 * Deterministic dictation cleanup — a line-by-line port of the Mac app's Sources/EvooCore/DictationRules.swift,
 * kept in step with it by the shared cases in src/test/resources/rules.tsv (exported from the Swift tests):
 *  • filler words:     "um so we should ship"               → "so we should ship"
 *  • stutters:         "we could we could push it"          → "we could push it"
 *  • self-corrections: "let's meet tomorrow, no, day after tomorrow" → "let's meet day after tomorrow"
 */
object DictationRules {
    data class Result(val text: String, val unresolved: Boolean)

    fun apply(input: String): Result {
        var tokens = removeCommaFillers(normalizeMeridiem(input)).split(Regex("\\s+")).filter { it.isNotEmpty() }
            .map { Token(it) }.toMutableList()
        tokens = removeFillers(tokens)
        tokens = removeStutters(tokens)
        tokens = collapseValueCorrections(tokens)
        tokens = collapseEchoNegations(tokens)
        tokens = collapseRestatements(tokens)
        val unresolved = booleanArrayOf(false)
        tokens = applyCorrections(tokens, unresolved)
        return Result(render(tokens), unresolved[0])
    }

    // region Tokens

    class Token(var raw: String) {
        /** Lowercased letters/digits only — used for matching. */
        val norm: String get() = normalize(raw)
        val endsClause: Boolean get() = raw.lastOrNull()?.let { it in ",;:" } ?: false
        val endsSentence: Boolean get() = raw.lastOrNull()?.let { it in ".?!" } ?: false

        /** The word without trailing punctuation, keeping the original casing. */
        val bare: String get() = raw.trimEnd(',', ';', ':', '.', '?', '!')
        val trailingPunctuation: String get() = raw.substring(bare.length)

        fun copy() = Token(raw)

        companion object {
            fun normalize(s: String): String =
                s.lowercase().filter { it.isLetterOrDigit() || it == ':' }.trim(':')
        }
    }

    // endregion
    // region Fillers & stutters

    private const val FILLERS = "(?:like|you know|basically|so yeah|so basically|kind of|sort of|literally|okay so)"

    /** Spoken fillers the speech model sets off with commas: "…to, like, give…", "You know, we…", "So yeah, …". */
    fun removeCommaFillers(text: String): String {
        var out = text
        out = out.replace(Regex("(?i),\\s*(?:you know|so basically|basically|so yeah|okay so),\\s*"), ", ")
        out = out.replace(Regex("(?i),\\s*$FILLERS,\\s*"), " ")
        out = Regex("(?i)(^|[.!?]\\s+)you know,?\\s+((?:we|i|they|he|she|there|so|my|our)\\b)").replace(out) { m ->
            val next = m.groupValues[2]
            m.groupValues[1] + next.take(1).uppercase() + next.drop(1)
        }
        out = out.replace(Regex("(?i),\\s*you know(?=[.!?]|$)"), "")
        // "…to like give you…" → "…to give you…" ("I'd like to" keeps its "like").
        out = Regex("(?i)\\bto like (\\w+)").replace(out) { m ->
            if (Verbs.isVerb(m.groupValues[1])) "to " + m.groupValues[1] else m.value
        }
        // Sentence start: "Like, engineering…" → "Engineering…"
        out = Regex("(?i)(^|[.!?]\\s+)$FILLERS,?\\s+(\\w)").replace(out) { m ->
            val matched = m.value
            if (matched.contains(",") || matched.lowercase().contains("so ")) m.groupValues[1] + m.groupValues[2].uppercase()
            else matched
        }
        return out
    }

    /** Small words a comma never really follows ("to, Wednesday"). */
    private val glueWords = setOf("to", "the", "a", "an", "and", "of", "on", "in", "at", "for", "from", "with",
        "is", "was", "are", "be", "my", "your", "our", "their", "his", "her", "by")
    private val fillers = setOf("um", "umm", "uh", "uhh", "uhm", "erm", "er", "hmm", "mm", "mhm", "ah")

    fun removeFillers(tokens: List<Token>): MutableList<Token> {
        val out = mutableListOf<Token>()
        for ((i, t) in tokens.withIndex()) {
            // "Um, so, uh, I think…": a "so" wedged between fillers is a filler too.
            val isFiller = t.norm in fillers || (t.norm == "so" && t.raw.endsWith(",") &&
                ((i > 0 && tokens[i - 1].norm in fillers) || (i + 1 < tokens.size && tokens[i + 1].norm in fillers)))
            if (isFiller) {
                // "to, um, Wednesday" → "to Wednesday": the comma only framed the filler.
                val last = out.lastOrNull()
                if (t.endsClause && last != null && last.endsClause && last.norm in glueWords) last.raw = last.bare
                // Keep sentence-ending punctuation the filler carried ("… ship it, um." → "… ship it.").
                if (t.endsSentence && out.isNotEmpty()) {
                    val l = out.last()
                    l.raw = l.bare + t.trailingPunctuation
                }
                continue
            }
            out.add(t)
        }
        return out
    }

    /** Real one- and two-letter words, so only broken-off starts are dropped. */
    private val shortWords = setOf("a", "i", "an", "am", "as", "at", "be", "by", "do", "go", "he", "hi", "if",
        "in", "is", "it", "me", "my", "no", "of", "oh", "ok", "on", "or", "so", "to", "up", "us", "we", "ah", "ha", "yo")

    /** Common three-letter words, which are never treated as broken-off starts ("the theory", "car carpet"). */
    private val commonThreeLetter = setOf(
        "the", "and", "for", "you", "are", "but", "not", "all", "any", "can", "had", "her", "was", "one", "our",
        "out", "day", "get", "has", "him", "his", "how", "man", "new", "now", "old", "see", "two", "way", "who",
        "did", "its", "let", "put", "say", "she", "too", "use", "car", "cat", "dog", "big", "bad", "yes", "yet",
        "got", "may", "run", "sit", "top", "red", "far", "few", "own", "off", "end", "why", "ask", "men", "per",
        "art", "pay", "buy", "fun", "job", "law", "map", "sun", "war", "air", "age", "key", "low", "set", "try",
    )

    /** Words that are legitimately doubled in normal speech ("I know that that is…", "had had"). */
    private val legitDoubles = setOf("that", "had", "is", "very", "really", "bye", "no", "ha")

    fun removeStutters(tokens: List<Token>): MutableList<Token> {
        // Broken-off word starts: "like m make it" → "like make it", "your dis dictionary" → "your dictionary".
        var t = tokens.filterIndexed { i, tok ->
            if (i + 1 >= tokens.size || tok.endsClause || tok.endsSentence) return@filterIndexed true
            val w = tok.norm
            val next = tokens[i + 1].norm
            if (w.isEmpty() || !w.all { it.isLetter() } || next.firstOrNull() != w.first()) return@filterIndexed true
            val head = next.take(w.length)
            val mismatches = head.zip(w).count { it.first != it.second }
            val fragment = (w.length <= 2 && next.startsWith(w) && w !in shortWords && next.length > w.length) ||
                (w.length == 3 && mismatches <= 1 && w !in commonThreeLetter && next.length >= 6)
            !fragment
        }.toMutableList()
        t = removeRestarts(t)
        var changed = true
        while (changed) {
            changed = false
            outer@ for (n in 4 downTo 1) {
                if (t.size < 2 * n) continue
                for (i in 0..(t.size - 2 * n)) {
                    val a = t.subList(i, i + n).map { it.norm }
                    val b = t.subList(i + n, i + 2 * n).map { it.norm }
                    if (a != b || a.contains("") || (n == 1 && a[0] in legitDoubles)) continue
                    // Keep the second copy — it carries the punctuation that follows. If ASR put a sentence
                    // break inside the stutter ("we could. We could"), undo the capital it added.
                    val wasLowercase = t[i].raw.firstOrNull()?.isLowerCase() == true
                    repeat(n) { t.removeAt(i) }
                    if (wasLowercase && (i == 0 || !t[i - 1].endsSentence) && t[i].raw.isNotEmpty()) {
                        t[i].raw = t[i].raw.take(1).lowercase() + t[i].raw.drop(1)
                    }
                    changed = true
                    break@outer
                }
            }
        }
        return t
    }

    /** Openers people restart with ("if it sounds… if it's unusual", "when we… when we're done"). */
    private val restartOpeners = setOf("if", "when", "i", "we", "you", "it", "so", "and", "but", "because",
        "the", "this", "that", "they", "he", "she", "there", "what", "can")

    /** A phrase started, abandoned, and started again: "if it sounds if it's unusual" → "if it's unusual". */
    fun removeRestarts(input: List<Token>): MutableList<Token> {
        val t = input.toMutableList()
        var i = 0
        while (i + 3 < t.size) {
            val a = t[i].norm
            val b = t[i + 1].norm
            if (a !in restartOpeners) { i += 1; continue }
            var restarted = false
            for (j in (i + 2)..minOf(i + 5, t.size - 2)) {
                if (t[j].norm != a || t[j + 1].norm == b || !t[j + 1].norm.startsWith(b) || b.length < 2) continue
                // Nothing between the two starts may end a clause — that would be two real phrases.
                if (t.subList(i, j).any { it.endsClause || it.endsSentence }) break
                repeat(j - i) { t.removeAt(i) }
                restarted = true
                break
            }
            if (!restarted) i += 1
        }
        return t
    }

    // endregion
    // region a.m. / p.m.

    /** "4 p.m." → "4 PM" so the dots aren't mistaken for sentence ends ("at 4 p.m. 5 p.m."). */
    fun normalizeMeridiem(text: String): String {
        var out = text.replace(Regex("(?i)\\b([ap])\\.\\s?m\\.(?=\\s*$|\\s+[A-Z])"), "$1M.")
        out = out.replace(Regex("(?i)\\b([ap])\\.\\s?m\\.?"), "$1M")
        return out.replace("aM", "AM").replace("pM", "PM")
    }

    // endregion
    // region Value corrections

    private val replacingCues = setOf("no", "sorry", "actually", "wait", "rather", "correction", "make", "meant", "nahi")
    private val cueFiller = replacingCues + setOf("not", "i", "mean", "it", "that", "or", "oh")

    /** Multi-word dates: "day after tomorrow", "next week", "this Friday", "the weekend". */
    private val datePhrases = listOf(
        listOf("day", "after", "tomorrow"), listOf("day", "before", "yesterday"), listOf("the", "day", "after"),
        listOf("the", "week", "after"), listOf("the", "week", "after", "next"),
        listOf("next", "week"), listOf("this", "week"), listOf("next", "month"), listOf("this", "month"),
        listOf("next", "year"), listOf("this", "weekend"), listOf("next", "weekend"), listOf("the", "weekend"),
        listOf("tomorrow", "morning"), listOf("tomorrow", "evening"), listOf("tomorrow", "night"), listOf("tonight"),
        listOf("this", "evening"), listOf("this", "morning"),
    )
    private val weekdayPrefixes = setOf("next", "this", "coming", "last")

    /**
     * Chains of times/numbers or days joined by correction words; the last value that survives wins.
     *   "at 4, not 4 PM, 5 PM" → "at 5 PM";  "on Monday, sorry, Tuesday" → "on Tuesday";  "at 5, not 4" → unchanged
     */
    fun collapseValueCorrections(input: List<Token>): MutableList<Token> {
        val t = input.toMutableList()
        var i = 0
        while (i < t.size) {
            val first = valueGroup(t, i)
            if (first == null) { i += 1; continue }
            var kept = first
            var last = first
            var corrected = false
            var awaitingRestatement = false
            var j = first.last + 1
            while (j < t.size) {
                // The words between two values must all be correction words (or nothing but a comma).
                var k = j
                while (k < t.size && t[k].norm in cueFiller) k += 1
                val gap = t.subList(j, k).map { it.norm }
                val next = valueGroup(t, k) ?: break
                if (groupClass(t, next) != groupClass(t, first)) break
                val replaces = gap.any { it in replacingCues } || gap.contains("mean")
                val negates = gap.contains("not")
                val commaOnly = gap.isEmpty() && t[last.last].endsClause
                if (negates && !replaces) {
                    awaitingRestatement = true // "not 4 PM" — that value is rejected
                } else if (replaces || (gap.isEmpty() && awaitingRestatement) || (commaOnly && corrected)) {
                    kept = next
                    corrected = true
                    awaitingRestatement = false
                } else break
                last = next
                j = next.last + 1
            }
            if (corrected) {
                val replacement = t.subList(kept.first, kept.last + 1).map { it.copy() }
                val tail = t[last.last].trailingPunctuation
                if (replacement.isNotEmpty()) {
                    val end = replacement.last()
                    end.raw = end.bare + (if (tail.any { it in ".?!" }) tail.last().toString() else "")
                }
                repeat(last.last + 1 - first.first) { t.removeAt(first.first) }
                t.addAll(first.first, replacement)
                i = first.first + replacement.size
            } else {
                i = first.last + 1
            }
        }
        return t
    }

    /** A run of tokens forming one value: "4 PM", "3:30", "five thirty", "Tuesday", "day after tomorrow". */
    private fun valueGroup(t: List<Token>, i: Int): IntRange? {
        if (i >= t.size) return null
        val phrase = datePhrases.filter { matches(it, t, i) }.maxByOrNull { it.size }
        if (phrase != null) return i until i + phrase.size
        if (t[i].norm in weekdayPrefixes && i + 1 < t.size && wordKind(t[i + 1].norm) == WordKind.WEEKDAY && !t[i].endsClause) {
            return i until i + 2 // "next Monday"
        }
        val cls = valueClass(t[i]) ?: return null
        var end = i + 1
        // A group ends at punctuation or after AM/PM ("4 PM 5 PM" is two times).
        while (end < t.size && !t[end - 1].endsClause && !t[end - 1].endsSentence &&
            t[end - 1].norm !in setOf("am", "pm") && valueClass(t[end]) == cls) end += 1
        return i until end
    }

    private val dateWords = setOf("day", "week", "weekend", "month", "year", "morning", "evening", "night")

    private fun groupClass(t: List<Token>, group: IntRange): Int? =
        if (group.count() > 1 && group.any { valueClass(t[it]) == 1 || t[it].norm in dateWords }) 1
        else valueClass(t[group.first])

    /** "…play tomorrow, not tomorrow, day after tomorrow" / "send it to John, not John, Mike". */
    fun collapseEchoNegations(input: List<Token>): MutableList<Token> {
        val t = input.toMutableList()
        var i = 1
        while (i < t.size) {
            // "to be or not to be", "whether or not", "like it or not" aren't corrections.
            if (t[i].norm != "not" || t[i - 1].endsSentence || t[i - 1].norm == "or") { i += 1; continue }
            var echoed = 0
            for (k in minOf(3, i) downTo 1) {
                if (i + k >= t.size) continue
                val before = t.subList(i - k, i).map { it.norm }
                val after = t.subList(i + 1, i + k + 1).map { it.norm }
                if (before == after) { echoed = k; break }
            }
            var start = i - echoed
            // Partial echo: "2 laptops, not 2, 3 laptops" repeats only the first word of what's taken back.
            if (echoed == 0 && i + 1 < t.size && t[i - 1].raw.endsWith(",")) {
                val j = (maxOf(0, i - 3) until i).lastOrNull { t[it].norm == t[i + 1].norm }
                if (j != null) { echoed = 1; start = j }
            }
            val restStart = i + 1 + echoed
            // Needs a replacement after the echo, in the same sentence: "not tomorrow, <day after tomorrow>".
            if (echoed <= 0 || restStart >= t.size || t[restStart - 1].endsSentence) { i += 1; continue }
            repeat(restStart - start) { t.removeAt(start) }
            if (start > 0) t[start - 1].raw = t[start - 1].bare // drop a comma left dangling
            i = start + 1
        }
        return t
    }

    private val intensifiers = setOf("very", "really", "so", "super", "extremely", "quite", "too", "pretty",
        "totally", "absolutely", "completely", "much", "way")
    /** Words that may sit between a word and its restatement: "bad, not no bad, very bad". */
    private val restatementFillers = intensifiers + setOf("not", "no", "i", "mean", "sorry", "actually", "like", "or", "rather")

    /** A word said again with a sharper modifier replaces the first attempt: "still bad, very bad" → "still very bad". */
    fun collapseRestatements(input: List<Token>): MutableList<Token> {
        val t = input.toMutableList()
        var changed = true
        while (changed) {
            changed = false
            for (i in t.indices) {
                val w = t[i].norm
                if (w.isEmpty() || w in functionWords || w in restatementFillers || t[i].endsSentence) continue
                // The same word again within 5 words, with only fillers in between.
                val j = ((i + 1) until minOf(t.size, i + 6)).firstOrNull { t[it].norm == w } ?: continue
                if (j <= i + 1 || !t.subList(i + 1, j).all { it.norm in restatementFillers }) continue
                // Keep the modifiers directly before the restated word ("very"), drop the rest.
                var keepFrom = j
                while (keepFrom > i + 1 && t[keepFrom - 1].norm in intensifiers && !t[keepFrom - 1].endsClause) keepFrom -= 1
                if (!(keepFrom < j || t.subList(i + 1, j).any { it.norm !in intensifiers })) continue
                repeat(keepFrom - i) { t.removeAt(i) }
                changed = true
                break
            }
        }
        return t
    }

    private fun valueClass(token: Token): Int? = when (wordKind(token.norm)) {
        WordKind.NUMBER -> 0
        WordKind.WEEKDAY, WordKind.RELATIVE_DAY, WordKind.MONTH -> 1
        null -> if (token.norm == "oclock") 0 else null
    }

    // endregion
    // region Self-corrections

    /** Words that can make up a correction cue, e.g. "no", "no sorry", "actually make that", "I mean". */
    private val cueWords = setOf("no", "sorry", "wait", "actually", "nahi", "nahin", "matlab")
    private val cuePhrases = listOf(
        listOf("i", "mean"), listOf("make", "that"), listOf("make", "it"), listOf("or", "rather"),
        listOf("scratch", "that"), listOf("correction"), listOf("mera", "matlab"),
    )
    /** Cue words that also occur in normal speech; they only count when set off by punctuation or combined. */
    private val weakCues = setOf("no", "sorry", "wait", "actually", "make that", "make it", "correction")

    private class Cue(val start: Int, val end: Int, val isScratch: Boolean)

    private sealed class Plan {
        /** Drop everything from `at` and continue with the repair; `unit` words said after the old value are kept. */
        class Truncate(val at: Int, val unit: List<String> = emptyList()) : Plan()
        /** Replace the word at `index` in place ("CC Tom on the email, I mean Tim" → "CC Tim on the email"). */
        class Swap(val index: Int) : Plan()
    }

    private fun lastSentenceEnd(t: List<Token>, before: Int): Int? =
        (before - 1 downTo 0).firstOrNull { t[it].endsSentence }

    fun applyCorrections(input: List<Token>, unresolved: BooleanArray): MutableList<Token> {
        val tokens = input.toMutableList()
        var searchFrom = 0
        while (true) {
            val cue = findCue(tokens, searchFrom) ?: break
            var sentenceStart = lastSentenceEnd(tokens, cue.start)?.let { it + 1 } ?: 0
            // ASR often ends the sentence at the hesitation: "at 3:30. Actually make it 4." —
            // the cue opens a new sentence, so the correction applies to the previous one.
            if (sentenceStart == cue.start && sentenceStart > 0 && !cue.isScratch) {
                sentenceStart = lastSentenceEnd(tokens, sentenceStart - 1)?.let { it + 1 } ?: 0
            }
            val prefix = tokens.subList(sentenceStart, cue.start).toList()
            val repairEnd = (cue.end until tokens.size).firstOrNull { tokens[it].endsSentence }?.let { it + 1 } ?: tokens.size
            val repair = tokens.subList(cue.end, repairEnd).toList()

            if (cue.isScratch) {
                // "scratch that" deletes what came before it in the sentence, or the previous sentence.
                var start = sentenceStart
                if (prefix.isEmpty() && sentenceStart > 0) {
                    start = lastSentenceEnd(tokens, sentenceStart - 1)?.let { it + 1 } ?: 0
                }
                repeat(cue.end - start) { tokens.removeAt(start) }
                searchFrom = start
                continue
            }
            val plan = if (prefix.isNotEmpty() && repair.isNotEmpty()) plan(prefix, repair) else null
            if (plan == null) {
                unresolved[0] = true
                searchFrom = cue.end
                continue
            }
            val fixed: MutableList<Token>
            when (plan) {
                is Plan.Truncate -> {
                    val body = repair.map { it.copy() }.toMutableList()
                    if (plan.unit.isNotEmpty() && body.isNotEmpty()) {
                        // "5." + ["boxes"] → "5 boxes."
                        val last = body.removeAt(body.size - 1)
                        val end = last.trailingPunctuation
                        last.raw = last.bare
                        body.add(last)
                        body.addAll(plan.unit.map { Token(it) })
                        body.last().raw += end
                    }
                    fixed = (prefix.subList(0, plan.at).map { it.copy() } + body).toMutableList()
                    if (plan.at == 0 && fixed.isNotEmpty()) fixed[0].raw = capitalized(fixed[0].raw)
                    if (plan.at > 0) fixed[plan.at - 1].raw = fixed[plan.at - 1].bare // drop the comma that led into the cue
                }
                is Plan.Swap -> {
                    fixed = prefix.map { it.copy() }.toMutableList()
                    val i = plan.index
                    val tail = fixed[i].trailingPunctuation
                    fixed.removeAt(i)
                    fixed.addAll(i, repair.map { Token(it.bare) })
                    fixed[i + repair.size - 1].raw += tail
                    // The sentence's end moves from the repair to the (unchanged) prefix.
                    val end = repair.lastOrNull()?.trailingPunctuation ?: ""
                    fixed[fixed.size - 1].raw = fixed[fixed.size - 1].bare + end
                }
            }
            repeat(repairEnd - sentenceStart) { tokens.removeAt(sentenceStart) }
            tokens.addAll(sentenceStart, fixed)
            searchFrom = sentenceStart
        }
        return tokens
    }

    private fun findCue(t: List<Token>, from: Int): Cue? {
        var i = from
        while (i < t.size) {
            var j = i
            val parts = mutableListOf<String>()
            // Greedily consume consecutive cue words/phrases: "no, sorry, I mean".
            while (j < t.size) {
                val phrase = cuePhrases.firstOrNull { matches(it, t, j) }
                if (phrase != null) {
                    parts.add(phrase.joinToString(" "))
                    j += phrase.size
                } else if (t[j].norm in cueWords) {
                    parts.add(t[j].norm)
                    j += 1
                } else break
                if (t[j - 1].endsSentence) break
            }
            if (parts.isNotEmpty()) {
                val isScratch = parts.contains("scratch that")
                val setOff = (i > 0 && (t[i - 1].endsClause || t[i - 1].endsSentence)) || t[j - 1].endsClause
                val strong = parts.size > 1 || parts.any { it !in weakCues }
                if (i > 0 && (isScratch || strong || setOff)) return Cue(i, j, isScratch)
                i = j
            } else {
                i += 1
            }
        }
        return null
    }

    private fun matches(phrase: List<String>, t: List<Token>, i: Int): Boolean {
        if (i + phrase.size > t.size) return false
        for ((k, w) in phrase.withIndex()) {
            if (t[i + k].norm != w) return false
            if (k < phrase.size - 1 && t[i + k].endsSentence) return false
        }
        return true
    }

    private val determiners = setOf("a", "an", "the", "this", "that", "my", "your", "our", "their", "his", "her", "next", "last")
    private val functionWords = setOf("him", "her", "it", "them", "me", "you", "us", "the", "a", "an", "to",
        "of", "in", "on", "at", "for", "and", "or", "is", "was")
    /** A sentence that stops on one of these was abandoned mid-thought ("I think we should, actually…"). */
    private val danglingEnds = setOf("should", "could", "would", "will", "can", "might", "must", "to", "the",
        "a", "an", "and", "but", "or", "so", "gonna", "wanna", "we", "i", "just")

    private fun plan(prefix: List<Token>, repair: List<Token>): Plan? {
        val head = repair[0].norm
        // 1. The repair restarts from a word already said: "to Rahul, sorry, to Priya".
        prefix.indexOfLast { it.norm == head }.takeIf { it >= 0 }?.let { return Plan.Truncate(it) }
        // 2. Same kind of value: numbers/times, weekdays, months, relative days.
        val kind = wordKind(head)
        if (kind != null) {
            var end = prefix.size
            while (end > 0 && wordKind(prefix[end - 1].norm) != kind) end -= 1
            if (end > 0) {
                var start = end - 1
                while (start > 0 && wordKind(prefix[start - 1].norm) == kind) start -= 1
                // A bare new value keeps the old value's unit: "3 boxes, actually 5" → "5 boxes".
                val bareValue = repair.all { wordKind(it.norm) == kind }
                val unit = if (bareValue) prefix.subList(end, prefix.size).map { it.bare }.filter { it.isNotEmpty() } else emptyList()
                return Plan.Truncate(start, if (unit.size <= 2) unit else emptyList())
            }
        }
        // 3. Restart from an article: "a 7 out of 10, actually an 8", "next week, no, the week after".
        if (head in determiners) {
            prefix.indexOfLast { it.norm in determiners }.takeIf { it >= 0 }?.let { return Plan.Truncate(it) }
        }
        // 4. A new action replaces the old one: "Email him, no, call him" → "Call him".
        if (startsWithVerb(repair) && startsWithVerb(prefix)) return Plan.Truncate(0)
        // 5. The first attempt was abandoned mid-phrase: "I think we should, actually let's ship it".
        if (prefix.last().norm in danglingEnds) return Plan.Truncate(0)
        // 6. A name replaces a name: "CC Tom on the email, I mean Tim", "Call John, sorry, Mike".
        if (repair.size <= 2 && repair.all { it.bare.firstOrNull()?.isUpperCase() == true }) {
            val i = (1 until prefix.size).lastOrNull {
                prefix[it].bare.firstOrNull()?.isUpperCase() == true && prefix[it].norm != "i" && wordKind(prefix[it].norm) == null
            }
            if (i != null) return Plan.Swap(i)
        }
        // 7. The repair ends on a content word already said: "meet tomorrow, no, day after tomorrow".
        val lastWord = repair.last().norm
        if (lastWord !in functionWords) {
            prefix.indexOfLast { it.norm == lastWord }.takeIf { it >= 0 }?.let { return Plan.Truncate(it) }
        }
        // 8. A one-word repair replaces the last word: "Buy apples, no, oranges", "blue, actually green".
        //    Never a pronoun: "I love you, I mean it" is not a correction.
        if (repair.size == 1 && prefix.size > 1 && head !in functionWords) return Plan.Truncate(prefix.size - 1)
        return null
    }

    /** Whether the phrase opens with a verb (the Mac app asks Apple's tagger; here: a list of common verbs). */
    private fun startsWithVerb(tokens: List<Token>): Boolean {
        if (tokens.isEmpty() || tokens[0].norm in functionWords) return false
        return Verbs.isVerb(tokens[0].norm)
    }

    enum class WordKind { NUMBER, WEEKDAY, MONTH, RELATIVE_DAY }

    private val numberWords = setOf(
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
        "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
        "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "million",
        "half", "quarter", "noon", "midnight",
    )
    private val weekdays = setOf("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
    private val months = setOf("january", "february", "march", "april", "may", "june", "july", "august", "september",
        "october", "november", "december")
    private val relativeDays = setOf("today", "tomorrow", "tonight", "yesterday", "kal", "parso", "aaj")

    fun wordKind(w: String): WordKind? = when {
        w.firstOrNull()?.isDigit() == true || w in numberWords || w == "am" || w == "pm" -> WordKind.NUMBER
        w in weekdays -> WordKind.WEEKDAY
        w in months -> WordKind.MONTH
        w in relativeDays -> WordKind.RELATIVE_DAY
        else -> null
    }

    // endregion
    // region Rendering

    private fun render(tokens: List<Token>): String {
        val words = tokens.map { it.raw }.toMutableList()
        // Re-capitalize after sentence ends and at the start.
        for (i in words.indices) if (i == 0 || tokens[i - 1].endsSentence) words[i] = capitalized(words[i])
        return words.joinToString(" ")
    }

    private fun capitalized(s: String): String {
        val f = s.firstOrNull() ?: return s
        return if (f.isLowerCase()) f.uppercase() + s.drop(1) else s
    }
    // endregion
}
