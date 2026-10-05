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

    @Test fun polishPromptIsTheMacApps() {
        // Exported from the Mac app with: evoo-cli prompt-prefix > android/core/src/test/resources/polish-prefix.txt
        assertEquals(javaClass.getResource("/polish-prefix.txt")!!.readText(), RefinePrompt.prefix)
    }

    @Test fun polishGuards() {
        assertEquals("Let's meet Monday.", RefinePrompt.accept("<think>\n\n</think>\n\nLet's meet Monday.<|im_end|>", "let's meet monday"))
        // The model answered instead of cleaning, or lost a "not": keep the rules' text.
        assertEquals(null, RefinePrompt.accept("Photosynthesis is the process by which plants turn light, water and carbon dioxide into sugar and oxygen, using chlorophyll in their leaves to capture energy.", "can you explain photosynthesis"))
        assertEquals(null, RefinePrompt.accept("I'm in the office Friday.", "I'm in the office Monday not Friday"))
        assertTrue(RefinePrompt.needsPolish("So basically we could like ship it on Friday I guess."))
        assertTrue(!RefinePrompt.needsPolish("The design team finished the new screens last night."))
        assertTrue(RefinePrompt.suffix("hi there", "Earlier.").contains("<earlier>Earlier.</earlier>"))
    }

    companion object { const val MAX_KNOWN_DIFFERENCES = 0 }
}
