import Foundation

/// A small "did you know" shown by the floating pill after a dictation, introducing one feature at a time.
public struct Tip: Equatable, Sendable {
    public let id: String
    public let text: String
    public let example: String

    public init(id: String, text: String, example: String) {
        self.id = id
        self.text = text
        self.example = example
    }
}

/// When to introduce which feature. The first tip comes after 5 dictations (the basics are familiar by then),
/// then the gaps widen so it never feels naggy: at most one tip per dictation, and one every ~10–25 uses.
public enum Tips {
    public static let all: [Tip] = [
        Tip(id: "corrections", text: "Change your mind mid-sentence — Evoo keeps what you meant.",
            example: "let's meet tomorrow, no, Friday"),
        Tip(id: "commands", text: "Evoo can act, not just type. Say the whole command:",
            example: "open Slack"),
        Tip(id: "shortcuts", text: "Set up voice shortcuts in Settings, then say:",
            example: "my email"),
        Tip(id: "lists", text: "Speak a list and Evoo formats it:",
            example: "I need to buy milk, eggs and bread"),
        Tip(id: "editing", text: "Fix what you just said without the keyboard:",
            example: "replace Tuesday with Wednesday"),
        Tip(id: "spotlight", text: "Find anything on your Mac:",
            example: "search my Mac for tax documents"),
        Tip(id: "reminders", text: "Add reminders and events by voice:",
            example: "remind me to call Divya tomorrow at 5"),
        Tip(id: "notes", text: "Save a thought, find it later by meaning:",
            example: "note: pricing idea, tiered plans"),
        Tip(id: "keys", text: "Hands busy? Keyboard shortcuts by voice:",
            example: "new tab"),
        Tip(id: "windows", text: "Arrange windows by voice:",
            example: "move this to the left half"),
        Tip(id: "dictionary", text: "Names coming out wrong? Add them in Settings → Personal dictionary, or just fix one once — Evoo learns."
            , example: ""),
        Tip(id: "search", text: "Search the web without typing:",
            example: "ask ChatGPT what to cook with eggs and spinach"),
        Tip(id: "readAloud", text: "Select any text, then say:",
            example: "read this aloud"),
        Tip(id: "transcribe", text: "Turn recordings into text and subtitles:",
            example: "transcribe a file"),
        Tip(id: "history", text: "Everything you dictate is searchable — menu → History & Notes, or say:",
            example: "what did I say about the invoice"),
    ]

    /// Dictation counts at which the 1st, 2nd, 3rd… tip appears.
    public static let schedule = [5, 12, 20, 30, 42, 55, 70, 85, 100, 120, 140, 165, 190, 220, 250]

    /// The tip to show after the `uses`-th dictation, if one is due.
    public static func next(afterUses uses: Int, shown: Set<String>, extra: [Tip] = []) -> Tip? {
        let pending = (all + extra).filter { !shown.contains($0.id) }
        let index = shown.count
        guard let first = pending.first, index < schedule.count, uses >= schedule[index] else { return nil }
        return first
    }
}
