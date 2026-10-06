import Foundation

/// Several commands in one breath: "close the tab and switch to Claude", "mute, then open Slack",
/// "Copy that. New tab. Paste."
///
/// A dictation only counts as a chain when *every* piece is a command on its own — so ordinary sentences with
/// "and" in them ("buy milk and eggs", "search Google for salt and pepper") are never split.
public enum CommandChain {
    public static let maxSteps = 6

    /// The steps, in order, or nil when the dictation isn't a chain of commands.
    public static func parts(_ dictation: String, isCommand: (String) -> Bool) -> [String]? {
        let text = dictation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 300 else { return nil }
        // Joined by "and", "then", "and then", "after that", or just a pause the speech model wrote as , ; .
        let separator = #"(?i)\s*[,;.]?\s+(?:and then|and after that|after that|and also|and|then|next)\s+|\s*[,;.]\s+"#
        let pieces = text.replacingOccurrences(of: separator, with: "\u{1F}", options: .regularExpression)
            .split(separator: "\u{1F}")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".,;!?"))) }
            .filter { !$0.isEmpty }
        guard pieces.count >= 2, pieces.count <= maxSteps, pieces.allSatisfy(isCommand) else { return nil }
        return pieces
    }

    /// What the pill shows when the chain is done: "Close the tab → Switch to Claude".
    public static func summary(_ parts: [String]) -> String {
        parts.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " → ")
    }
}
