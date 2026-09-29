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

/// When to introduce which feature: the first tip after 5 dictations, then one every 4 — skipping any
/// feature the user already uses, so tips stop once they've found everything.
public enum Tips {
    public static let all: [Tip] = [
        Tip(id: "corrections", text: "Change your mind", example: "tomorrow, no, Friday"),
        Tip(id: "commands", text: "Open any app", example: "open Slack"),
        Tip(id: "lists", text: "Speak a list", example: "buy milk, eggs and bread"),
        Tip(id: "editing", text: "Fix by voice", example: "replace Tuesday with Wednesday"),
        Tip(id: "search", text: "Search the web", example: "search Google for flights"),
        Tip(id: "shortcuts", text: "Voice shortcuts — set up in Settings", example: "my email"),
        Tip(id: "spotlight", text: "Find files", example: "search my Mac for invoices"),
        Tip(id: "reminders", text: "Set reminders", example: "remind me to call Mom at 5"),
        Tip(id: "notes", text: "Quick notes", example: "note: pricing idea"),
        Tip(id: "keys", text: "Keyboard by voice", example: "new tab"),
        Tip(id: "windows", text: "Arrange windows", example: "move this to the left half"),
        Tip(id: "history", text: "Find past dictations", example: "what did I say about rent"),
        Tip(id: "readAloud", text: "Hear text aloud (select it first)", example: "read this aloud"),
        Tip(id: "transcribe", text: "Transcribe recordings", example: "transcribe a file"),
        Tip(id: "dictionary", text: "Fix a name once — Evoo learns it", example: ""),
    ]

    public static let firstAfter = 5
    public static let every = 4

    /// The tip to show after the `uses`-th dictation, if one is due. `lastTipAt` is the dictation count when the
    /// previous tip was shown (0 if never); `skip` holds tips already shown and features already used.
    public static func next(afterUses uses: Int, lastTipAt: Int, skip: Set<String>, extra: [Tip] = []) -> Tip? {
        let due = lastTipAt == 0 ? uses >= firstAfter : uses - lastTipAt >= every
        guard due else { return nil }
        return (all + extra).first { !skip.contains($0.id) }
    }
}
