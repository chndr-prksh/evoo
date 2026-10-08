@testable import EvooCore
import Foundation
import Testing

@Suite struct HotkeyGestureTests {
    @Test func holdStartsAndReleaseStops() {
        var g = HotkeyGesture(mode: .hold)
        #expect(g.handle(.fnDown(at: 0)) == .start)
        #expect(g.handle(.fnUp(at: 1.0)) == .stop)
        #expect(g.phase == .idle)
    }

    @Test func holdTooShortCancels() {
        var g = HotkeyGesture(mode: .hold)
        _ = g.handle(.fnDown(at: 0))
        #expect(g.handle(.fnUp(at: 0.1)) == .cancel)
    }

    @Test func fnPlusArrowCancels() {
        var g = HotkeyGesture(mode: .hybrid)
        #expect(g.handle(.fnDown(at: 0)) == .start)
        #expect(g.handle(.otherKey(at: 0.05)) == .cancel)
    }

    @Test func toggleNeedsDoubleTapThenSingleTapStops() {
        var g = HotkeyGesture(mode: .toggle)
        #expect(g.handle(.fnDown(at: 0)) == nil)
        #expect(g.handle(.fnUp(at: 0.05)) == nil)
        #expect(g.handle(.fnDown(at: 0.2)) == .start)
        #expect(g.handle(.fnUp(at: 0.25)) == nil)
        #expect(g.handle(.fnDown(at: 5)) == .stop)
    }

    @Test func toggleSlowTapsDoNothing() {
        var g = HotkeyGesture(mode: .toggle)
        _ = g.handle(.fnDown(at: 0))
        #expect(g.handle(.fnDown(at: 1)) == nil)
        #expect(g.timeout(now: 2) == nil)
        #expect(g.phase == .idle)
    }

    @Test func hybridLongHoldIsHoldToTalk() {
        var g = HotkeyGesture(mode: .hybrid)
        #expect(g.handle(.fnDown(at: 0)) == .start)
        #expect(g.handle(.fnUp(at: 2)) == .stop)
    }

    @Test func hybridDoubleTapLatchesHandsFree() {
        var g = HotkeyGesture(mode: .hybrid)
        #expect(g.handle(.fnDown(at: 0)) == .start)
        #expect(g.handle(.fnUp(at: 0.08)) == nil)
        #expect(g.handle(.fnDown(at: 0.2)) == nil) // keeps recording
        #expect(g.handle(.fnUp(at: 0.26)) == nil)
        #expect(g.isRecording)
        #expect(g.handle(.fnDown(at: 10)) == .stop)
    }

    @Test func hybridSingleTapTimesOutAsCancel() {
        var g = HotkeyGesture(mode: .hybrid)
        _ = g.handle(.fnDown(at: 0))
        _ = g.handle(.fnUp(at: 0.08))
        #expect(g.timeout(now: 0.2) == nil) // still inside the window
        #expect(g.timeout(now: 0.5) == .cancel)
    }
}

@Suite struct TextTests {
    @Test func removesWhisperHallucinations() {
        #expect(TextCleaner.clean(" Thank you for watching. ") == "")
        #expect(TextCleaner.clean("[BLANK_AUDIO]") == "")
        #expect(TextCleaner.clean("hello   [Music]  world") == "hello world")
    }

    @Test func speechRangeTrimsSilence() {
        let silence = [Float](repeating: 0, count: 16000) // 1 s
        let tone = (0 ..< 16000).map { Float(sin(Double($0) * 0.1)) * 0.2 }
        let clip = silence + tone + silence + silence
        let r = AudioStats.speechRange(clip)!
        #expect(r.lowerBound == 16000 - 2400) // 150 ms lead pad
        #expect(r.upperBound == 32000 + 4000) // 250 ms tail pad
        #expect(AudioStats.speechRange(silence) == nil)
        #expect(AudioStats.endsInPause(clip))
        #expect(!AudioStats.endsInPause(silence + tone))
    }

    @Test func timesReadNaturally() {
        #expect(TextCleaner.tidyTimes("at 04:00 P.M., 05:00 p.m..") == "at 4 PM, 5 PM.")
        #expect(TextCleaner.tidyTimes("at 04:30 p.m.") == "at 4:30 PM.")
        #expect(TextCleaner.tidyTimes("Dinner at 08:00 p.m. Then drinks.") == "Dinner at 8 PM. Then drinks.")
        #expect(TextCleaner.tidyTimes("at 9 a.m. sharp") == "at 9 AM sharp")
        #expect(TextCleaner.tidyTimes("Wait... ok") == "Wait... ok")
    }

    @Test func silenceDetection() {
        #expect(AudioStats.isLikelySilent([Float](repeating: 0.001, count: 16000)))
        let tone = (0 ..< 16000).map { Float(sin(Double($0) * 0.1)) * 0.2 }
        #expect(!AudioStats.isLikelySilent(tone))
    }

    @Test func promptContainsCorrectionExampleAndTranscript() {
        let p = RefinePrompt.chatML(transcript: "hello there", language: .english)
        #expect(p.contains("day after tomorrow"))
        #expect(p.hasSuffix("<think>\n\n</think>\n\n"))
        #expect(p.contains("<transcript>hello there</transcript>"))
        #expect(!p.contains("Parso")) // Hinglish shots only for Hinglish
        #expect(RefinePrompt.chatML(transcript: "x", language: .hinglish).contains("Roman"))
    }

    @Test func acceptRejectsChattyOutput() {
        let input = "let's meet tomorrow no day after tomorrow"
        #expect(RefinePrompt.accept(refined: "\"Let's meet day after tomorrow.\"", input: input)
            == "Let's meet day after tomorrow.")
        let essay = String(repeating: "Sure! Here is a detailed plan for your meeting. ", count: 5)
        #expect(RefinePrompt.accept(refined: essay, input: input) == nil)
        #expect(RefinePrompt.accept(refined: "   ", input: input) == nil)
    }

    @Test func fastPathSkipsCleanDictation() {
        #expect(!RefinePrompt.needsRefinement("Hey team, the build is green.", language: .english))
        #expect(RefinePrompt.needsRefinement("let's meet tomorrow, no, day after tomorrow", language: .english))
        #expect(RefinePrompt.needsRefinement("um push it to next week", language: .english))
        #expect(RefinePrompt.needsRefinement("we we should ship", language: .english))
        #expect(RefinePrompt.needsRefinement("I mean Monday", language: .english))
        #expect(RefinePrompt.needsRefinement("kal milte hain", language: .hinglish))
    }

    @Test func engineRouting() {
        #expect(EnginePreference.automatic.resolve(for: .english) == .parakeet)
        #expect(EnginePreference.automatic.resolve(for: .hinglish) == .hinglish)
        #expect(EnginePreference.parakeet.resolve(for: .hindi) == .whisper) // Parakeet has no Hindi
    }
}

@Suite struct DictationRulesTests {
    func fix(_ s: String) -> String { DictationRules.apply(s).text }

    @Test func selfCorrections() {
        #expect(fix("Let's meet tomorrow, no, day after tomorrow.") == "Let's meet day after tomorrow.")
        #expect(fix("Send the invoice to Rahul, sorry, to Priya by Friday.") == "Send the invoice to Priya by Friday.")
        #expect(fix("The meeting is at 3:30 actually make it 4.") == "The meeting is at 4.")
        #expect(fix("Ship it on Friday, actually make that Monday.") == "Ship it on Monday.")
        #expect(fix("Call John, sorry, Mike.") == "Call Mike.")
        #expect(fix("I'll call you at 6, no wait, 7:30.") == "I'll call you at 7:30.")
        #expect(fix("Send the deck, no, the report.") == "Send the report.")
        // The speech model put full stops around the cue: the repair isn't a new sentence.
        #expect(fix("Let's meet tomorrow. No. Day after tomorrow.") == "Let's meet day after tomorrow.")
        #expect(fix("Send it to Rahul. Sorry. To Priya by Friday.") == "Send it to Priya by Friday.")
        #expect(fix("Call John. Sorry. Mike.") == "Call Mike.")
    }

    @Test func leavesNormalSpeechAlone() {
        #expect(fix("There is no milk in the fridge.") == "There is no milk in the fridge.")
        #expect(fix("No, I don't think so.") == "No, I don't think so.")
        #expect(fix("I actually like this design.") == "I actually like this design.")
        #expect(fix("We can make it work.") == "We can make it work.")
        #expect(fix("I know that that is hard.") == "I know that that is hard.")
    }

    @Test func fillersAndStutters() {
        #expect(fix("Um, so we could, we could push the launch.") == "So we could push the launch.")
        #expect(fix("I think uh we should ship.") == "I think we should ship.")
        #expect(fix("The the build is green.") == "The build is green.")
    }

    @Test func valueChains() {
        #expect(fix("Hey, I'm planning to go out tomorrow at 4 not 4 PM, 5 PM.") == "Hey, I'm planning to go out tomorrow at 5 PM.")
        #expect(fix("Hey, I'm planning to go out tomorrow at 4, not 4 p.m. 5 p.m.") == "Hey, I'm planning to go out tomorrow at 5 PM.")
        #expect(fix("Let's meet on Monday, sorry, Tuesday.") == "Let's meet on Tuesday.")
        #expect(fix("Call me at 5, not 4.") == "Call me at 5, not 4.")
        #expect(fix("I'm going tomorrow, not today.") == "I'm going tomorrow, not today.")
        #expect(fix("Pick 3, 4, 5 of them.") == "Pick 3, 4, 5 of them.")
        #expect(fix("It starts at 6 p.m.") == "It starts at 6 PM.")
        #expect(fix("Dinner at 8 p.m. Then drinks.") == "Dinner at 8 PM. Then drinks.")
    }

    @Test func correctionPhrasings() {
        let cases: [(String, String)] = [
            ("I want to go to play tomorrow not tomorrow, day after tomorrow.", "I want to go to play day after tomorrow."),
            ("I want to go to play tomorrow, not tomorrow, day after tomorrow.", "I want to go to play day after tomorrow."),
            ("I want to go to play tomorrow, no, day after tomorrow.", "I want to go to play day after tomorrow."),
            ("I want to go to play tomorrow, sorry, day after tomorrow.", "I want to go to play day after tomorrow."),
            ("I want to go to play tomorrow, actually day after tomorrow.", "I want to go to play day after tomorrow."),
            ("Let's meet next week, no, this Friday.", "Let's meet this Friday."),
            ("Let's meet on Monday, not Monday, next Tuesday.", "Let's meet on next Tuesday."),
            ("Send it to John, not John, Mike.", "Send it to Mike."),
            ("Book the table for 6, not 6, 8 people.", "Book the table for 8 people."),
            ("I'm free tomorrow, not today.", "I'm free tomorrow, not today."),
            ("It's not bad, not bad at all.", "It's not bad at all."), // repeated phrase removed, like a stutter
            ("I do not know.", "I do not know."),
            ("It's still bad very bad.", "It's still very bad."),
            ("The dictation is still bad, not no bad, very bad.", "The dictation is still very bad."),
            ("It was good, really good.", "It was really good."),
            ("Bad news and bad weather.", "Bad news and bad weather."),
            ("It is very, very good.", "It is very, very good."),
        ]
        for (input, expected) in cases {
            #expect(fix(input) == expected, "\(input)")
        }
    }

    @Test func asrSentenceBreaks() {
        #expect(fix("The meeting is at 3.30. Actually make it 4.") == "The meeting is at 4.")
        #expect(fix("I was thinking we could. We could push the launch.") == "I was thinking we could push the launch.")
        #expect(fix("Let's meet tomorrow or no, day after tomorrow.") == "Let's meet day after tomorrow.")
    }

    @Test func brokenOffWordStarts() {
        #expect(fix("Make it skippable, like m make it simple.") == "Make it skippable, like make it simple.")
        #expect(fix("Th the plan is ready.") == "The plan is ready.")
        #expect(fix("I am in a meeting.") == "I am in a meeting.")
        #expect(fix("Go to the store.") == "Go to the store.")
        #expect(fix("Start adding those words in your dis dictionary.") == "Start adding those words in your dictionary.")
        #expect(fix("Read the theory first.") == "Read the theory first.")
        #expect(fix("Add it if it sounds if it's unusual.") == "Add it if it's unusual.")
        #expect(fix("If it rains, if it snows, we stay.") == "If it rains, if it snows, we stay.")
        #expect(fix("When we're done we leave.") == "When we're done we leave.")
    }

    @Test func scratchThat() {
        #expect(fix("I love pizza. Scratch that. I love pasta.") == "I love pasta.")
    }

    @Test func ambiguousCorrectionIsFlagged() {
        let r = DictationRules.apply("I love you, I mean it.")
        #expect(r.unresolved)
        #expect(r.text == "I love you, I mean it.")
    }
}

@Suite struct PersonalDictionaryTests {
    let known: Set<String> = ["hi", "how", "are", "you", "the", "river", "was", "calm", "rave", "walk",
                              "tell", "that", "and", "will", "review", "call", "ask", "to", "join", "with", "iphone"]
    let dict = PersonalDictionary(["Divya", "Aarav", "Kavya", "iPhone", "Kubernetes"])

    func fix(_ s: String) -> String { dict.apply(s) { known.contains($0) } }

    @Test func fixesMisheardNames() {
        #expect(fix("Hi DeVeo, how are you?") == "Hi Divya, how are you?")
        #expect(fix("Can you ask Rav to join?") == "Can you ask Aarav to join?")
        #expect(fix("Tell Cavya that") == "Tell Kavya that")
    }

    @Test func neverTouchesRealWords() {
        #expect(fix("The river was calm by the rave.") == "The river was calm by the rave.")
        #expect(fix("I walked with you.") == "I walked with you.")
    }

    @Test func normalizesCasing() {
        #expect(fix("my iphone and kubernetes") == "my iPhone and Kubernetes")
    }

    @Test func multiWordTerms() {
        let d = PersonalDictionary(["Wispr Flow", "Divya"])
        let known: Set<String> = ["faster", "than", "whisper", "flow", "the", "river", "is", "not", "accurate"]
        func f(_ s: String) -> String { d.apply(s) { known.contains($0) } }
        #expect(f("Faster than whisperflow, but not accurate.") == "Faster than Wispr Flow, but not accurate.")
        #expect(f("Faster than whisper flow.") == "Faster than Wispr Flow.")
        #expect(f("The river flow is not accurate.") == "The river flow is not accurate.")
        #expect(f("your name Deva.") == "your name Divya.")
        let withDeva = PersonalDictionary(["Divya"])
        let dict: Set<String> = ["deva", "your", "name", "a", "is", "god"]
        #expect(withDeva.apply("take your name Deva.") { dict.contains($0) } == "take your name Divya.") // heard as a name
        #expect(withDeva.apply("a deva is a god.") { dict.contains($0) } == "a deva is a god.") // real word, lowercase
        #expect(withDeva.apply("Deva is a god.") { dict.contains($0) } == "Deva is a god.") // sentence start: unknown
    }

    @Test func ignoresUnrelatedUnknownWords() {
        #expect(fix("Zorblat is here") == "Zorblat is here")
    }
}

@Suite struct FormatterTests {
    func md(_ s: String) -> String { DictationFormatter.format(s, style: .markdown) }
    func plain(_ s: String) -> String { DictationFormatter.format(s, style: .plain) }

    @Test func shoppingList() {
        #expect(md("I have a list of items that I want to buy tomorrow bread, egg, milk, avocado, apple, banana.")
            == "I have a list of items that I want to buy tomorrow:\n- Bread\n- Egg\n- Milk\n- Avocado\n- Apple\n- Banana")
        #expect(plain("We need three things: milk, eggs and bread.")
            == "We need three things:\n• Milk\n• Eggs\n• Bread")
    }

    @Test func listAfterSentenceBreak() {
        #expect(plain("E.g., I will try to create a list. Avocado, egg, banana, milk, water.")
            == "E.g., I will try to create a list:\n• Avocado\n• Egg\n• Banana\n• Milk\n• Water")
        #expect(plain("Avocado, egg, banana and milk.") == "• Avocado\n• Egg\n• Banana\n• Milk")
        #expect(plain("I like red, blue and green.") == "I like red, blue and green.")
    }

    @Test func checklist() {
        #expect(md("My to-do list for today call the bank, pay rent, book tickets.")
            == "My to-do list for today:\n- [ ] Call the bank\n- [ ] Pay rent\n- [ ] Book tickets")
    }

    @Test func numberedList() {
        #expect(md("To deploy, first run the tests, second build the app, third push to production.")
            == "To deploy:\n1. Run the tests\n2. Build the app\n3. Push to production.")
        #expect(md("Step one open settings. Step two click privacy.")
            == "1. Open settings\n2. Click privacy.")
    }

    @Test func proseStaysProse() {
        #expect(md("I met John, Mary, and Steve at the cafe yesterday.") == "I met John, Mary, and Steve at the cafe yesterday.")
        #expect(md("At first I was unsure, but it worked.") == "At first I was unsure, but it worked.")
        #expect(md("Please look at google.com for details.") == "Please look at google.com for details.")
        #expect(md("Can you bring the charger, the cable, and the adapter?") == "Can you bring the charger, the cable, and the adapter?")
        #expect(md("We need to talk, but not now, maybe later.") == "We need to talk, but not now, maybe later.")
    }

    @Test func spokenBreaks() {
        #expect(plain("Hi team new line the build is green new paragraph thanks Chandra.")
            == "Hi team\nThe build is green\n\nThanks Chandra.")
    }

    @Test func emails() {
        #expect(plain("My email is chandra at gmail.com and the site is evoo.app.")
            == "My email is chandra@gmail.com and the site is evoo.app.")
    }

    @Test func terminalsGetOneLine() {
        #expect(DictationFormatter.format("I want to buy bread, eggs, milk new line done", style: .singleLine)
            == "I want to buy bread, eggs, milk done")
        #expect(OutputStyle.forApp("com.apple.Terminal") == .singleLine)
        #expect(OutputStyle.forApp("notion.id") == .markdown)
        #expect(OutputStyle.forApp("com.apple.mail") == .plain)
    }
}

@Suite struct ContextVocabularyTests {
    let known: Set<String> = ["hey", "how", "are", "you", "the", "meeting", "today", "online", "last", "seen", "message", "type", "rose"]

    @Test func harvestsNamesFromScreen() {
        let screen = ["Divya", "online", "Hey Divya, how are you?", "Priyanka: the meeting is today", "Type a message",
                      "Rose", "GitHub OKR"]
        let names = ContextVocabulary.names(from: screen) { known.contains($0) }
        #expect(names.first == "Divya") // most frequent
        #expect(names.contains("Priyanka"))
        #expect(names.contains("GitHub"))
        #expect(names.contains("OKR"))
        #expect(!names.contains("Hey"))
        #expect(!names.contains("Rose")) // a real word — too risky to force
        #expect(!names.contains("Type"))
        // Capitalized ordinary words on screen are not names.
        let shouting = ContextVocabulary.names(from: ["HELLO, HOW ARE YOU?"]) { known.union(["hello"]).contains($0) }
        #expect(shouting.isEmpty)
    }

    @Test func screenNamesFixMisheardName() {
        let names = ContextVocabulary.names(from: ["Divya", "online"]) { known.contains($0) }
        let dict = PersonalDictionary(names)
        let words: Set<String> = known.union(["deva", "take", "your", "name"])
        #expect(dict.apply("take your name Deva.") { words.contains($0) } == "take your name Divya.")
    }
}

@Suite struct CorrectionPromptTests {
    @Test func parsesAnswers() {
        #expect(CorrectionPrompt.parse("3-4") == [2, 3])
        #expect(CorrectionPrompt.parse("2, 6-8") == [1, 5, 6, 7])
        #expect(CorrectionPrompt.parse("none") == [])
        #expect(CorrectionPrompt.parse("Sure! The answer is") == nil)
    }

    @Test func appliesDeletions() {
        #expect(CorrectionPrompt.apply([2, 3], to: "Let's meet tomorrow, no, day after tomorrow.") == "Let's meet day after tomorrow.")
        #expect(CorrectionPrompt.apply([0, 1, 2], to: "Email him, no, call him.") == "Call him.")
        #expect(CorrectionPrompt.apply([0, 1, 2], to: "Ask Sarah, no, ask Emma to review it.") == "Ask Emma to review it.")
    }

    @Test func rejectsUnsafeEdits() {
        #expect(CorrectionPrompt.apply([0, 1], to: "Call him now please.") == nil) // no cue deleted
        #expect(CorrectionPrompt.apply([0, 1, 2, 3], to: "no no no no") == nil) // deletes everything
        #expect(CorrectionPrompt.apply([9], to: "short text") == nil) // out of range
    }
}

@Suite struct CommandTests {
    func run(_ s: String) -> (String, DictationCommands.Action?) {
        let p = DictationCommands.parse(s)
        return (DictationCommands.applyCasing(p.casing, to: p.text), p.action)
    }

    @Test func casing() {
        #expect(run("Capitalize each word, the lord of the rings.").0 == "The Lord Of The Rings.")
        #expect(run("capitalise every word my name is divya").0 == "My Name Is Divya")
        #expect(run("Title case: project kickoff notes").0 == "Project Kickoff Notes")
        #expect(run("All caps, urgent please read.").0 == "URGENT PLEASE READ.")
        #expect(run("Lowercase, Hello World.").0 == "hello world.")
    }

    @Test func quotesAndActions() {
        #expect(run("He said quote I'll be there end quote.").0 == "He said \"I'll be there\".")
        let (text, action) = run("See you soon, press enter.")
        #expect(text == "See you soon")
        #expect(action == .pressEnter)
        #expect(run("Undo that.").1 == .undo)
        #expect(run("Delete that").1 == .undo)
    }

    @Test func ordinarySpeechIsUntouched() {
        #expect(run("I love capital cities.").0 == "I love capital cities.")
        #expect(run("Don't delete that file.").1 == nil)
        #expect(run("Press enter when you're ready to continue the setup.").1 == nil)
        #expect(run("The quote was too expensive.").0 == "The quote was too expensive.")
    }
}

@Suite struct LearningTests {
    @Test func learnsCorrectedName() {
        let l = EditLearner.lessons(inserted: "Hi Deva, how are you?", edited: "Hi Divya, how are you?")
        #expect(l.contains(.word(heard: "Deva", meant: "Divya")))
    }

    @Test func learnsHabitsAndIgnoresAddedText() {
        let l = EditLearner.lessons(inserted: "Sounds good, see you at 5.", edited: "sounds good, see you at 5 😀 bring snacks")
        #expect(l.contains(.finalPeriod(dropped: true)))
        #expect(l.contains(.firstLetter(lowered: true)))
        #expect(!l.contains { if case .word = $0 { true } else { false } })
    }

    @Test func ignoresRewrites() {
        #expect(EditLearner.lessons(inserted: "Let's meet tomorrow at 5.", edited: "Actually can we do Friday instead").isEmpty)
    }

    @Test func habitsKickInAfterRepeatedEdits() {
        var habits = LearnedHabits()
        let app = "net.whatsapp.WhatsApp"
        habits.record([.finalPeriod(dropped: true)], app: app)
        #expect(habits.adapt("See you soon.", app: app) { _ in false } == "See you soon.") // once isn't a habit
        habits.record([.finalPeriod(dropped: true), .firstLetter(lowered: true)], app: app)
        habits.record([.firstLetter(lowered: true)], app: app)
        #expect(habits.adapt("See you soon.", app: app) { _ in false } == "see you soon")
        #expect(habits.adapt("Divya is here.", app: app) { $0 == "Divya" } == "Divya is here") // names stay capitalized
        #expect(habits.adapt("See you soon.", app: "com.apple.mail") { _ in false } == "See you soon.") // per app
    }
}

@Suite struct SnippetTests {
    let snippets = [Snippet(trigger: "my email", expansion: "chandra@example.com"),
                    Snippet(trigger: "my address", expansion: "12 Main St, Apt 4\nKent, WA 98032"),
                    Snippet(trigger: "my work email", expansion: "c@work.com")]

    @Test func wholeDictationIsExpandedVerbatim() {
        let m = Snippets.mask("My address.", snippets: snippets)
        #expect(m.isWholeDictation)
        #expect(m.text == "12 Main St, Apt 4\nKent, WA 98032")
    }

    @Test func inlineTriggersSurviveProcessing() {
        let m = Snippets.mask("Send it to my work email and my email.", snippets: snippets)
        #expect(!m.isWholeDictation)
        let processed = DictationRules.apply(m.text).text.uppercased() // anything the pipeline might do
        #expect(Snippets.unmask(processed, m.restore) == "SEND IT TO c@work.com AND chandra@example.com.")
    }

    @Test func noTriggerNoChange() {
        let m = Snippets.mask("Email me later.", snippets: snippets)
        #expect(m.text == "Email me later." && m.restore.isEmpty)
    }
}

@Suite struct VoiceEditTests {
    @Test func parses() {
        #expect(VoiceEdit.parse("Replace Tuesday with Wednesday.") == .replace(old: "Tuesday", new: "Wednesday"))
        #expect(VoiceEdit.parse("change 5 PM to 6 PM") == .replace(old: "5 PM", new: "6 PM"))
        #expect(VoiceEdit.parse("Delete the last sentence.") == .deleteLastSentence)
        #expect(VoiceEdit.parse("delete last word") == .deleteLastWord)
        #expect(VoiceEdit.parse("Make that a numbered list.") == .makeList(numbered: true))
        #expect(VoiceEdit.parse("Turn it into bullet points") == .makeList(numbered: false))
        #expect(VoiceEdit.parse("I need to change my plans.") == nil)
    }

    @Test func applies() {
        let last = "Let's meet on Tuesday at 5 PM. Bring the slides."
        #expect(VoiceEdit.replace(old: "tuesday", new: "wednesday").apply(to: last, style: .plain)
            == "Let's meet on Wednesday at 5 PM. Bring the slides.")
        #expect(VoiceEdit.deleteLastSentence.apply(to: last, style: .plain) == "Let's meet on Tuesday at 5 PM.")
        #expect(VoiceEdit.deleteLastWord.apply(to: "Send it now.", style: .plain) == "Send it.")
        #expect(VoiceEdit.makeList(numbered: false).apply(to: "We need milk, eggs and bread.", style: .plain)
            == "We need:\n• Milk\n• Eggs\n• Bread")
        #expect(VoiceEdit.makeList(numbered: true).apply(to: "Open settings, click privacy, and allow Evoo.", style: .plain)
            == "1. Open settings\n2. Click privacy\n3. Allow Evoo")
        #expect(VoiceEdit.replace(old: "Friday", new: "Monday").apply(to: last, style: .plain) == nil)
    }
}

@Suite struct RewritePromptTests {
    @Test func recognizesInstructions() {
        #expect(RewritePrompt.isInstruction("Make this more formal."))
        #expect(RewritePrompt.isInstruction("rewrite it as a bullet list"))
        #expect(RewritePrompt.isInstruction("Can you shorten this"))
        #expect(RewritePrompt.isInstruction("Translate to Hindi"))
        #expect(!RewritePrompt.isInstruction("Thanks for the update, see you tomorrow."))
        #expect(!RewritePrompt.isInstruction("Make sure you bring the slides."))
    }
}

@Suite struct AppCommandTests {
    let targets = AppCommands.builtIn + Websites.all + [
        AppTarget(name: "Slack", bundleID: "com.tinyspeck.slackmacgap"),
        AppTarget(name: "Visual Studio Code", aliases: ["vs code", "code"], bundleID: "com.microsoft.VSCode"),
        AppTarget(name: "Google Chrome", aliases: ["chrome"], bundleID: "com.google.Chrome"),
    ]
    func parse(_ s: String) -> AppCommand? { AppCommands.parse(s, targets: targets) }
    func name(_ c: AppCommand?) -> String? {
        switch c { case let .open(t): "open \(t.name)"; case let .search(t, q): "search \(t.name): \(q)"
        case let .openIn(u, b): "\(u.absoluteString) in \(b.name)"
        case let .openURL(u): u.absoluteString; case nil: nil }
    }

    @Test func opensApps() {
        #expect(name(parse("Open Slack.")) == "open Slack")
        #expect(name(parse("switch to Chrome")) == "open Google Chrome")
        #expect(name(parse("Open VS Code.")) == "open Visual Studio Code")
        #expect(name(parse("Open github.com")) == "https://github.com")
        #expect(name(parse("Go to evoo dot app")) == "https://evoo.app")
    }

    @Test func websitesAndBrowsers() {
        #expect(name(parse("Open GitHub in Chrome.")) == "https://github.com in Google Chrome")
        #expect(name(parse("open gmail on chrome")) == "https://mail.google.com in Google Chrome")
        #expect(name(parse("Open hacker news")) == "open Hacker News")
        #expect(name(parse("go to prime video")) == "open Prime Video")
        #expect(name(parse("Open evoo.app in Chrome")) == "https://evoo.app in Google Chrome")
        #expect(name(parse("Open the report in Chrome")) == nil) // not a site
    }

    @Test func searchesAndAsks() {
        #expect(name(parse("Search Google for flights to Delhi.")) == "search Google: flights to Delhi")
        #expect(name(parse("search for lo-fi music on YouTube")) == "search YouTube: lo-fi music")
        #expect(name(parse("Google best biryani near me")) == "search Google: best biryani near me")
        #expect(name(parse("Ask ChatGPT how do tides work?")) == "search ChatGPT: how do tides work")
        #expect(AppCommands.searchURL(targets[0], query: "flights to Delhi")?.absoluteString
            == "https://www.google.com/search?q=flights%20to%20Delhi")
    }

    @Test func creates() {
        #expect(name(parse("New Google doc.")) == "https://docs.new")
        #expect(name(parse("create a new spreadsheet")) == "https://sheets.new")
        #expect(name(parse("New email about the invoice")) == "mailto:?subject=the%20invoice")
    }

    @Test func ordinaryDictationIsNotACommand() {
        #expect(parse("Open the file and check the numbers.") == nil)
        #expect(parse("I will open Slack later today.") == nil)
        #expect(parse("Can you search for the invoice?") == nil)
        #expect(parse("We need a new approach.") == nil)
        #expect(parse("Ask him to call me.") == nil)
    }
}

@Suite struct MacCommandTests {
    func p(_ s: String) -> MacCommand? { MacCommands.parse(s) }

    @Test func spotlightAndShortcuts() {
        #expect(p("Search my Mac for tax documents.") == .spotlight("tax documents"))
        #expect(p("spotlight quarterly report") == .spotlight("quarterly report"))
        #expect(p("Run shortcut Morning Routine.") == .runShortcut("Morning Routine"))
        #expect(p("run the focus mode shortcut") == .runShortcut("focus mode"))
    }

    @Test func keys() {
        #expect(p("New tab.") == .keys(KeyCombo("t", command: true), name: "New tab"))
        #expect(p("Press command shift T") == .keys(KeyCombo("t", command: true, shift: true), name: "command shift t"))
        #expect(p("press enter") == .keys(KeyCombo("return"), name: "enter"))
        #expect(p("Hit escape.") == .keys(KeyCombo("escape"), name: "escape"))
        #expect(p("press F5") == .keys(KeyCombo("f5"), name: "f5"))
    }

    @Test func systemAndWindows() {
        #expect(p("Set volume to 30.") == .volume(30))
        #expect(p("volume 80 percent") == .volume(80))
        #expect(p("Mute") == .mute(true))
        #expect(p("next song") == .media(.next))
        #expect(p("Pause the music") == .media(.playPause))
        #expect(p("Turn on dark mode") == .darkMode(true))
        #expect(p("light mode") == .darkMode(false))
        #expect(p("Move this to the left half.") == .window(.leftHalf))
        #expect(p("maximize this window") == .window(.maximize))
        #expect(p("Full screen") == .window(.fullScreen))
    }

    @Test func clicks() {
        #expect(p("Click Send.") == .click("Send"))
        #expect(p("press the reply all button") == .click("reply all"))
    }

    @Test func remindersAndEvents() {
        guard case let .reminder(task, due)? = p("Remind me to call Divya tomorrow at 5 PM.") else {
            Issue.record("not a reminder"); return
        }
        #expect(task == "Call Divya")
        #expect(due.map { Calendar.current.component(.hour, from: $0) } == 17)
        guard case let .reminder(task2, due2)? = p("remind me to pay rent tomorrow") else { Issue.record("no"); return }
        #expect(task2 == "Pay rent")
        #expect(due2.map { Calendar.current.component(.hour, from: $0) } == 9)
        guard case let .event(title, start, minutes)? = p("Schedule lunch with Raj on Friday at 1 PM.") else {
            Issue.record("not an event"); return
        }
        #expect(title == "Lunch with Raj")
        #expect(Calendar.current.component(.hour, from: start) == 13)
        #expect(minutes == 60)
        guard case let .event(t2, _, m2)? = p("schedule a call with the design team tomorrow at 3 PM for 45 minutes") else {
            Issue.record("no"); return
        }
        #expect(t2 == "Call with the design team")
        #expect(m2 == 45)
    }

    @Test func notesHistoryAudio() {
        #expect(p("Note: pricing idea, tiered plans for teams.") == .note("Pricing idea, tiered plans for teams"))
        #expect(p("take a note that the demo went well") == .note("The demo went well"))
        #expect(p("What did I say about the invoice?") == .askHistory("the invoice"))
        #expect(p("Read this aloud.") == .readAloud)
        #expect(p("stop reading") == .stopReading)
        #expect(p("Transcribe a file") == .transcribeFile)
    }

    @Test func ordinaryDictationIsNotACommand() {
        #expect(p("Copy the numbers into the sheet and send it.") == nil)
        #expect(p("Can you remind me what the plan was?") == nil)
        #expect(p("I'll schedule it once I hear back.") == nil)
        #expect(p("The volume of sales went up this quarter.") == nil)
        #expect(p("Please click on the link I sent you yesterday to see the whole proposal.") == nil)
        #expect(p("Press A") == nil)
    }
}

@Suite struct SearchAndSubtitleTests {
    @Test func findsByWordsAndMeaning() {
        let texts = ["Send the invoice to Priya by Friday.", "Let's meet for lunch tomorrow.", "The billing for March is overdue."]
        let r = SemanticSearch.rank("invoice", in: texts)
        #expect(r.first == 0)
        #expect(!r.contains(1))
    }

    @Test func buildsSubtitles() {
        let tokens = [("▁Hello", 0.0, 0.4), ("▁there.", 0.4, 0.9), ("▁How", 1.2, 1.4), ("▁are", 1.4, 1.5), ("▁you?", 1.5, 1.9)]
            .map { Subtitles.Timed(text: $0.0, start: $0.1, end: $0.2) }
        #expect(Subtitles.srt(tokens) == "1\n00:00:00,000 --> 00:00:00,900\nHello there.\n\n2\n00:00:01,200 --> 00:00:01,900\nHow are you?\n")
    }
}

@Suite struct ComposeTests {
    @Test func recognizesReplyAndTranslate() {
        #expect(ReplyPrompt.replyIntent("Reply saying Thursday works but not before 3.") == "Thursday works but not before 3.")
        #expect(ReplyPrompt.replyIntent("respond that I'll join late") == "I'll join late")
        #expect(ReplyPrompt.replyIntent("write a reply telling them we accept") == "we accept")
        #expect(ReplyPrompt.replyIntent("I replied to him yesterday.") == nil)
        #expect(ReplyPrompt.translation("Translate to Hindi, see you tomorrow at the station.")?.language == "Hindi")
        #expect(ReplyPrompt.translation("translate into French: good morning")?.text == "good morning")
        #expect(ReplyPrompt.translation("We need to translate the docs.") == nil)
    }

    @Test func toneByApp() {
        #expect(Tone.forApp("net.whatsapp.WhatsApp") == .casual)
        #expect(Tone.forApp("com.apple.mail") == .professional)
        #expect(Tone.forApp("com.apple.TextEdit") == .neutral)
        #expect(RefinePrompt.prefix(language: .english, tone: .casual).contains("casual"))
    }
}

@Suite struct TipTests {
    @Test func cadence() {
        #expect(Tips.next(afterUses: 4, lastTipAt: 0, skip: []) == nil)
        #expect(Tips.next(afterUses: 5, lastTipAt: 0, skip: [])?.id == "corrections")
        #expect(Tips.next(afterUses: 8, lastTipAt: 5, skip: ["corrections"]) == nil) // every 4
        #expect(Tips.next(afterUses: 9, lastTipAt: 5, skip: ["corrections"])?.id == "commands")
    }

    @Test func skipsFeaturesAlreadyUsed() {
        // They already open apps by voice, so the next tip moves on to lists.
        #expect(Tips.next(afterUses: 9, lastTipAt: 5, skip: ["corrections", "commands"])?.id == "lists")
        #expect(Tips.next(afterUses: 1000, lastTipAt: 1, skip: Set(Tips.all.map(\.id))) == nil)
    }
}

@Suite struct ScreenLearningTests {
    let known: Set<String> = ["the", "meeting", "online", "type", "message", "hello", "how", "are", "you", "project", "review"]

    @Test func harvestsLowercaseTermsOnlyWhenRepeated() {
        let names = ContextVocabulary.names(from: ["deploy with kubectl", "kubectl get pods", "one-off zqxw"]) {
            known.contains($0)
        }
        #expect(names.contains("kubectl"))
        #expect(!names.contains("zqxw"))
    }

    @Test func learnsAfterThreeDictations() {
        var lexicon = ScreenLexicon()
        #expect(lexicon.observe(["Divya", "Kubernetes"]).isEmpty)
        #expect(lexicon.observe(["Divya", "Divya"]).isEmpty) // counted once per dictation
        #expect(lexicon.observe(["Divya"]) == ["Divya"])
        #expect(lexicon.observe(["Divya"]).isEmpty) // only reported once
    }

    @Test func reportsWhichTermsFixedTheText() {
        let d = PersonalDictionary(["Divya", "Aarav"])
        let r = d.applyReporting("Hi Deva, how are you?") { known.contains($0) }
        #expect(r.text == "Hi Divya, how are you?")
        #expect(r.used == ["Divya"])
        #expect(d.applyReporting("Hi Divya.") { known.contains($0) }.used.isEmpty) // already right
    }
}

@Suite struct ClassNotesTests {
    @Test func voiceCommands() {
        #expect(MacCommands.parse("Search note Bayes theorem.") == .searchClassNotes("Bayes theorem"))
        #expect(MacCommands.parse("search my class notes for variance") == .searchClassNotes("variance"))
        #expect(MacCommands.parse("Start class notes") == .openClassNotes)
        #expect(MacCommands.parse("What did I say about the invoice?") == .askHistory("the invoice"))
    }

    @Test func promptCarriesSubjectAndTopic() {
        let p = ClassNotePrompt.suffix(subject: "Constitutional Law", lastTopic: "Due process", transcript: "…", thinkBlock: false)
        #expect(p.contains("Subject: Constitutional Law"))
        #expect(p.contains("Current topic: Due process"))
        #expect(ClassNotePrompt.lastTopic(in: ["## Bayes theorem\n- flips conditionals", "- more"]) == "Bayes theorem")
    }

    @Test func parsesStudyPack() {
        let pack = StudyPackPrompt.parse("""
        ## Summary
        Conditional probability updates beliefs. Bayes flips it.
        ## Key terms
        - **Conditional probability** — probability of A given B
        - **Independence** - knowing B says nothing about A
        ## Practice questions
        1. State Bayes' theorem.
        ## Flashcards
        - Q: What is $P(A\\mid B)$? | A: $P(A\\cap B)/P(B)$
        ## To do
        - None
        """)
        #expect(pack.summary.hasPrefix("- Conditional probability updates"))
        #expect(pack.terms.map(\.term) == ["Conditional probability", "Independence"])
        #expect(pack.questions == ["State Bayes' theorem."])
        #expect(pack.flashcards.first?.back == "$P(A\\cap B)/P(B)$")
        #expect(pack.todos.isEmpty)
    }

    @Test func marksReachThePrompt() {
        let p = ClassNotePrompt.suffix(subject: "Physics", lastTopic: nil, transcript: "…", marks: [.confusing], thinkBlock: false)
        #expect(p.contains("CONFUSING"))
    }

    @Test func writesBulletsWithoutAI() {
        let notes = LectureNotes.bullets(from: "Okay so um the variance measures how spread out the values are. Right? This is important for the exam, the variance of a sum of independent variables is the sum of variances.")
        #expect(notes.first == "- The variance measures how spread out the values are.")
        #expect(notes.contains { $0.hasPrefix("- ★ This is important for the exam") })
        #expect(!notes.contains { $0.contains("Right?") })
    }

    @Test func searchesAcrossClasses() {
        var a = ClassSession(title: "Probability 3")
        a.segments = [.init(time: 120, page: 1, text: "Bayes theorem lets us flip conditional probabilities.")]
        var b = ClassSession(title: "Probability 4")
        b.segments = [.init(time: 60, page: 0, text: "Random variables map outcomes to numbers.")]
        let hits = ClassSearch.search("Bayes theorem", in: [a, b])
        #expect(hits.first?.sessionID == a.id)
        #expect(hits.first?.time == 120)
    }
}

@Test func spokenVolumeAndKeyVariants() {
    for phrase in ["Volume 30", "Volume, thirty.", "volume thirty percent", "Set the volume to 30%.", "Turn the volume to thirty",
                   "Change volume to 30", "Volume at 30.", "Sound 30", "Reduce the volume to thirty"] {
        #expect(MacCommands.parse(phrase) == .volume(30), "\(phrase)")
    }
    #expect(MacCommands.parse("Volume thirty five.") == .volume(35))
    #expect(MacCommands.parse("Volume one hundred") == .volume(100))
    for phrase in ["Press space bar.", "Space bar.", "Spacebar", "Hit space.", "Press the space bar key", "press space"] {
        guard case let .keys(combo, _)? = MacCommands.parse(phrase) else {
            Issue.record("not a key: \(phrase)"); continue
        }
        #expect(combo.key == "space", "\(phrase)")
    }
    guard case let .keys(c, _)? = MacCommands.parse("Press command, shift, T.") else { Issue.record("cmd shift t"); return }
    #expect(c.command && c.shift && c.key == "t")
    #expect(MacCommands.parse("Click Send") == .click("Send"))
    #expect(MacCommands.parse("I turned the volume up to thirty at the party yesterday") == nil)
}

@Test func notesTidyDropsRepeatsAndUnearnedStars() {
    let existing = "## Bayes\n- $$P(A\\mid B)=\\frac{P(B\\mid A)P(A)}{P(B)}$$ ★ final\n- **prior** — P(A) before evidence"
    let fresh = "## Bayes\n- $$P(A\\mid B)=\\frac{P(B\\mid A)P(A)}{P(B)}$$\n- **posterior** — P(A|B) after evidence ★ exam\n- slide likely covers failures"
    let out = ClassNotePrompt.tidy(fresh, lastTopic: "Bayes", existing: existing, heard: "the posterior is P of A given B after")
    #expect(out == "- **posterior** — P(A|B) after evidence")
    // Stars stay when the professor stressed it.
    let starred = ClassNotePrompt.tidy("- **posterior** — after evidence ★ exam", lastTopic: nil, existing: "",
                                       heard: "this will be on the exam")
    #expect(starred.contains("★"))
    // Nothing new → nothing written.
    #expect(ClassNotePrompt.tidy("## Bayes\n- **prior** — P(A) before evidence", lastTopic: nil, existing: existing, heard: "") == "")
}

@Test func goldenSetRegressions() {
    // "X or not X" is never a correction.
    #expect(DictationRules.apply("to be or not to be").text.lowercased().contains("to be or not to be"))
    #expect(DictationRules.apply("I'll go whether or not it rains.").text.contains("whether or not it rains"))
    // Real echo corrections still work.
    #expect(DictationRules.apply("Let's go tomorrow, not tomorrow, day after tomorrow.").text.contains("day after tomorrow"))
    // "so" between fillers is a filler; a normal leading "So," stays.
    #expect(DictationRules.apply("Um, so, uh, I think we should ship it.").text == "I think we should ship it.")
    #expect(DictationRules.apply("So, what do you think?").text == "So, what do you think?")
    // Speech-model artifacts.
    #expect(TextCleaner.clean("Click Send. Send") == "Click Send.")
    #expect(TextCleaner.clean("Bye bye.") == "Bye bye.")
    #expect(TextCleaner.clean("at 7:30 p.m. on the 21st.") == "at 7:30 p.m on the 21st.")
    #expect(TextCleaner.tidyTimes("7.30 p.m.") .hasPrefix("7:30"))
    // "Mute" misheard.
    #expect(MacCommands.parse("Mude.") == .mute(true))
}

@Test func polishNeverDropsMeaning() {
    #expect(RefinePrompt.accept(refined: "Let's go to the park.", input: "Let's go to the park, no, not today.") == nil)
    #expect(RefinePrompt.accept(refined: "To be or not to be.", input: "\"to be or not to be\".") == nil)
    #expect(RefinePrompt.accept(refined: "I can't make it today.", input: "I can't, um, make it today.") != nil)
    // Lists: an ordinal after "in" still counts ("…sign in, third…").
    #expect(DictationFormatter.format("First open the app, second sign in, third click settings.", style: .markdown).contains("3."))
    #expect(!DictationFormatter.format("I can write the first draft this weekend.", style: .markdown).contains("1."))
}

@Test func keyClickIsNotSpeech() {
    var clip = [Float](repeating: 0.001, count: 32_000) // 2 s of quiet room
    for i in 800 ..< 1_300 { clip[i] = 0.3 * Float(sin(Double(i))) } // ~30 ms fn-key click
    for i in 30_400 ..< 30_900 { clip[i] = 0.3 * Float(sin(Double(i))) } // and on release
    #expect(AudioStats.hasNoSpeech(clip))
    var word = [Float](repeating: 0.001, count: 16_000)
    for i in 4_000 ..< 9_000 { word[i] = 0.1 * Float(sin(Double(i) * 0.05)) } // ~0.3 s "yes"
    #expect(!AudioStats.hasNoSpeech(word))
}

@Test func learnsWritingStyleFromEdits() {
    let wa = "net.whatsapp.WhatsApp"
    var pairs: [StylePair] = []
    for (e, s) in [("Hey, are you coming tonight?", "hey are you coming tonight"),
                   ("Sounds good, see you at 8.", "sounds good see you at 8"),
                   ("I'm going to be late.", "gonna be late"),
                   ("Can you call me when you're free?", "can you call me when you're free"),
                   ("Thanks, that works.", "thanks that works")] {
        pairs.append(StylePair(app: wa, evoo: e, sent: s))
    }
    let profile = PersonalStyle.profile(app: wa, pairs: pairs)
    #expect(profile?.summary?.contains("lowercase") == true)
    #expect(profile?.summary?.contains("no full stop") == true)
    let shots = PersonalStyle.examples(for: "Are you free tonight?", app: wa, pairs: pairs)
    #expect(shots.first?.sent.contains("tonight") == true)
    #expect(PersonalStyle.context(for: "Are you free tonight?", app: wa, pairs: pairs)?.contains("They sent:") == true)
    // A different message typed afterwards is not an edit of Evoo's text.
    #expect(!PersonalStyle.isUsable(StylePair(app: wa, evoo: "See you at 8.", sent: "Actually let me check my calendar first and get back to you")))
}

@Test func learnsRepeatedWordSwaps() {
    let wa = "net.whatsapp.WhatsApp"
    let pairs = [
        StylePair(app: wa, evoo: "I'm going to be late.", sent: "gonna be late"),
        StylePair(app: wa, evoo: "We're going to the park.", sent: "we're going to the park"), // kept: a place, not a habit
        StylePair(app: wa, evoo: "I'm going to call you.", sent: "gonna call u"),
        StylePair(app: wa, evoo: "Are you coming tonight?", sent: "are u coming tonight"),
        StylePair(app: wa, evoo: "Did you see it?", sent: "did u see it"),
    ]
    let rules = StyleRewrites.learn(pairs)[wa] ?? []
    #expect(rules.contains { $0.from == "you" && $0.to == "u" })
    #expect(StyleRewrites.apply("Are you free tomorrow?", rules: rules) == "Are u free tomorrow?")
    #expect(StyleRewrites.learn(pairs)["com.tinyspeck.slackmacgap"] == nil) // per app
}

@Test func commaFillersAreRemovedWordsAreKept() {
    #expect(DictationRules.removeCommaFillers("I wanted to, like, give you an update.") == "I wanted to give you an update.")
    #expect(DictationRules.removeCommaFillers("Like, engineering fixed most bugs.") == "Engineering fixed most bugs.")
    #expect(DictationRules.removeCommaFillers("Done. You know, we still need it.") == "Done. We still need it.")
    #expect(DictationRules.removeCommaFillers("So basically, Priya is on it.") == "Priya is on it.")
    #expect(DictationRules.removeCommaFillers("So yeah, let me know.") == "Let me know.")
    // Real words stay.
    #expect(DictationRules.removeCommaFillers("I like it a lot.") == "I like it a lot.")
    #expect(DictationRules.removeCommaFillers("You know the answer.") == "You know the answer.")
    #expect(DictationRules.removeCommaFillers("It looks like rain.") == "It looks like rain.")
    #expect(DictationRules.removeCommaFillers("Done. You know we still need it.").hasSuffix("We still need it."))
    #expect(DictationRules.removeCommaFillers("I wanted to like give you an update.") == "I wanted to give you an update.")
    #expect(DictationRules.removeCommaFillers("Send it tonight, you know.") == "Send it tonight.")
    #expect(DictationRules.removeCommaFillers("I would like to go.") == "I would like to go.")
    #expect(DictationRules.removeCommaFillers("Do you know the answer?") == "Do you know the answer?")
    // "I mean" is a correction cue, handled elsewhere.
    #expect(DictationRules.apply("Let's meet tomorrow, I mean, Friday.").text.contains("Friday"))
}

@Test func hinglishCorrections() {
    #expect(HinglishRules.apply("Kal milte hain, nahi, parson milte hain.") == "Parson milte hain.")
    #expect(HinglishRules.apply("Kal milte parson milte hain.") == "Parson milte hain.")
    #expect(HinglishRules.apply("Rahul ko message bhejo, sorry, Amit ko message bhejo.") == "Amit ko message bhejo.")
    #expect(HinglishRules.apply("Raahul ko message amit ko message bhejo.") == "Amit ko message bhejo.")
    #expect(HinglishRules.apply("Mujhe do nahin, teen tickets chahiye.") == "Mujhe teen tickets chahiye.")
    // Ordinary sentences stay.
    #expect(HinglishRules.apply("Mera phone kharab hai, tera phone theek hai.") == "Mera phone kharab hai, tera phone theek hai.")
    #expect(HinglishRules.apply("Main ghar ja raha hoon aur tum ghar aao.") == "Main ghar ja raha hoon aur tum ghar aao.")
    #expect(HinglishRules.apply("Please bhej do.") == "Please bhej do.")
    #expect(HinglishRules.apply("Payment ho gaya hai, screenshot bhej raha hoon.") == "Payment ho gaya hai, screenshot bhej raha hoon.")
}

struct ContextPromptTests {
    @Test func echoedContextIsDropped() {
        let context = "We're planning the product launch for next quarter."
        let out = RefinePrompt.dropEcho("We're planning the product launch for next quarter. The launch is in March.",
                                        context: context, input: "the lunch is in march")
        #expect(out == "The launch is in March.")
        // A dictation that really starts like the context is left alone.
        #expect(RefinePrompt.dropEcho("We're planning it.", context: "We're planning it.", input: "we're planning it")
            == "We're planning it.")
    }

    @Test func contextIsTrimmedToTheEnd() {
        let long = String(repeating: "word ", count: 200) + "last sentence here."
        let trimmed = RefinePrompt.trimmedContext(long)!
        #expect(trimmed.count <= RefinePrompt.maxContext)
        #expect(trimmed.hasSuffix("last sentence here."))
        #expect(RefinePrompt.trimmedContext("  ") == nil)
        #expect(RefinePrompt.suffix(transcript: "hi there", context: "Earlier.", thinkBlock: false).contains("<earlier>Earlier.</earlier>"))
    }
}

struct LanguageTests {
    @Test func europeanLanguagesUseTheBuiltInModelAndSkipEnglishRules() {
        #expect(DictationLanguage.european.count == 24)
        for l in DictationLanguage.european {
            #expect(l.parakeetSupported)
            #expect(!l.usesEnglishRules)
            #expect(l.code.count == 2)
            #expect(EnginePreference.automatic.resolve(for: l) == .parakeet)
        }
        #expect(Set(DictationLanguage.european.map(\.code)).count == 24)
        #expect(DictationLanguage.english.usesEnglishRules && DictationLanguage.hinglish.usesEnglishRules)
        #expect(EnginePreference.automatic.resolve(for: .english) == .parakeet)
        #expect(EnginePreference.automatic.resolve(for: .hinglish) == .hinglish)
        #expect(!DictationLanguage.hindi.parakeetSupported)
    }
}

struct CommandChainTests {
    let targets = AppCommands.builtIn + [AppTarget(name: "Slack", bundleID: "com.tinyspeck.slackmacgap"),
                                         AppTarget(name: "Google Chrome", aliases: ["chrome"], bundleID: "com.google.Chrome")]
    func chain(_ s: String) -> [String]? {
        CommandChain.parts(s) { MacCommands.parse($0) != nil || AppCommands.parse($0, targets: targets) != nil }
    }

    @Test func chainsOfCommands() {
        #expect(chain("Close the tab and switch to Claude.") == ["Close the tab", "switch to Claude"])
        #expect(chain("Mute, then open Slack") == ["Mute", "open Slack"])
        #expect(chain("Copy that. New tab. Paste.") == ["Copy that", "New tab", "Paste"])
        #expect(chain("Volume thirty and then open Chrome and new tab") == ["Volume thirty", "open Chrome", "new tab"])
        #expect(chain("search Google for flights to Delhi and switch to Slack") == ["search Google for flights to Delhi", "switch to Slack"])
        #expect(CommandChain.summary(["close the tab", "switch to Claude"]) == "Close the tab → Switch to Claude")
    }

    @Test func ordinarySpeechIsNeverSplit() {
        #expect(chain("Buy milk and eggs.") == nil)
        #expect(chain("Open Slack") == nil) // one command: handled as before
        #expect(chain("search Google for salt and pepper") == nil) // the whole thing is one search
        #expect(chain("I closed the tab and switched to Claude.") == nil)
        #expect(chain("Close the tab and tell me a joke") == nil)
        #expect(chain("Remind me to buy milk and eggs") == nil)
    }

    @Test func articlesInKeyCommands() {
        #expect(MacCommands.parse("Close the tab") == MacCommands.parse("close tab"))
        #expect(MacCommands.parse("close the current tab") == MacCommands.parse("close tab"))
        #expect(MacCommands.parse("refresh this page") != nil || MacCommands.parse("refresh the page") != nil)
    }
}

struct CommandModeGestureTests {
    /// Pressing Control while fn is held marks a command; it must not cancel the recording the way other keys do.
    @Test func otherKeysCancelButTheGestureItselfDoesNot() {
        var g = HotkeyGesture(mode: .hold)
        #expect(g.handle(.fnDown(at: 0)) == .start)
        // (fn + ⌃ is filtered out by the key monitor and never reaches the gesture as an "other key".)
        #expect(g.isRecording)
        #expect(g.handle(.otherKey(at: 0.5)) == .cancel)
    }
}
