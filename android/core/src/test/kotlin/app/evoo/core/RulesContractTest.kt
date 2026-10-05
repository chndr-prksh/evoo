package app.evoo.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** The Android rules must give the same answers as the Mac app's, on the Mac app's own test cases. */
class RulesContractTest {
    private val cases = javaClass.getResource("/rules.tsv")!!.readText().lines()
        .filter { it.isNotBlank() && !it.startsWith("#") }.map { it.split("\t") }.filter { it.size == 2 }

    @Test fun matchesTheMacApp() {
        assertTrue(cases.size >= 40, "rules.tsv is missing or short: ${cases.size} cases")
        val failures = cases.mapNotNull { (said, expected) ->
            val got = DictationRules.apply(said).text
            if (got == expected) null else "said:     $said\n  expected: $expected\n  got:      $got"
        }
        // Verb detection differs (Apple's tagger on the Mac, a word list here): allow a couple, show them all.
        println("rules contract: ${cases.size - failures.size}/${cases.size} match the Mac app")
        failures.forEach { println("MISMATCH\n  $it") }
        assertTrue(failures.size <= MAX_KNOWN_DIFFERENCES, "${failures.size} cases differ from the Mac app:\n" + failures.joinToString("\n"))
    }

    @Test fun pipelineBasics() {
        assertEquals("", EvooPipeline.process("[BLANK_AUDIO]").text)
        assertEquals("I think we should ship it on Friday.", EvooPipeline.process("Um, so, uh, I think we should, we should ship it on Friday.").text)
        assertEquals("I will call you, and I'm on my way.", EvooPipeline.process("i will call you, and i'm on my way.").text)
        assertEquals(" hello", EvooPipeline.spaced("hello", 'a'))
        assertEquals("hello", EvooPipeline.spaced("hello", ' '))
        assertEquals("hello", EvooPipeline.spaced("hello", null))
    }

    companion object { const val MAX_KNOWN_DIFFERENCES = 0 }
}
