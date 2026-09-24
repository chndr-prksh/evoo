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
        #expect(EnginePreference.automatic.resolve(for: .hinglish) == .whisper)
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

    @Test func asrSentenceBreaks() {
        #expect(fix("The meeting is at 3.30. Actually make it 4.") == "The meeting is at 4.")
        #expect(fix("I was thinking we could. We could push the launch.") == "I was thinking we could push the launch.")
        #expect(fix("Let's meet tomorrow or no, day after tomorrow.") == "Let's meet day after tomorrow.")
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
