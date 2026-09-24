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
