package app.evoo.core

/**
 * The Mac app asks Apple's language tagger whether a word is a verb; Android has no such tagger built in,
 * so this is a list of verbs people actually start instructions with ("email him, no, call him").
 */
object Verbs {
    fun isVerb(word: String): Boolean = word.lowercase().trim { !it.isLetter() } in verbs

    private val verbs: Set<String> = """
        accept add address adjust allow announce answer apply approve archive arrange ask assign attach avoid
        back be become begin believe book bring build buy call cancel carry catch change charge check choose
        clean clear click close collect come compare complete confirm connect consider contact continue copy
        correct cover create cut deal decide decline delay delete deliver describe design develop discuss do
        download draft draw drive drop eat edit email enable end enter explain export extend fax fill find
        finish fix follow forget forward get give go grab handle hand have hear help hold host include
        increase inform install introduce invite join keep know launch learn leave let listen look make manage
        mark meet mention merge message move need note notify offer open order organize pack paste pay phone
        pick ping plan play post prepare present press print proceed process publish pull push put raise reach
        read rebook receive record reduce refund register release remind remove rename rent repeat replace
        reply report request reschedule reserve reset resolve respond restart return review revert revise run
        save say schedule search see select sell send set share ship show sign skip slack sort speak spend
        split start stay stop submit suggest switch take talk tell test text thank think translate travel try
        turn type undo update upgrade upload use verify visit wait walk want watch work write
        let's lets
    """.trimIndent().split(Regex("\\s+")).filter { it.isNotEmpty() }.toSet()
}
