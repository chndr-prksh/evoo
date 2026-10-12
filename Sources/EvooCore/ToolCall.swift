import Foundation

/// One action the tool-calling model asked for: a tool from Tools/tools.json and its arguments.
public struct ToolCall: Equatable, Sendable {
    public var name: String
    /// Text and numbers both arrive as strings ("30", "Chrome"); `int(_:)` reads a number.
    public var args: [String: String]

    public init(name: String, args: [String: String] = [:]) {
        self.name = name
        self.args = args
    }

    public func int(_ key: String) -> Int? { args[key].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } }

    /// Every tool, in the order of Tools/tools.json. The model was fine-tuned with exactly this list in its prompt.
    public static let toolNames = [
        "open_app", "quit_app", "open_website", "web_search", "find_file", "press_keys", "edit", "browser",
        "scroll", "set_volume", "change_volume", "mute", "media", "brightness", "dark_mode", "window", "click",
        "system", "type_text", "add_reminder", "add_event", "set_timer", "set_alarm", "cancel_alarms", "save_note",
        "search_history", "compose_email", "get_directions", "rewrite_selection", "reply", "translate",
        "read_aloud", "class_notes", "run_shortcut", "transcribe_file", "no_action",
    ]

    /// What every prompt starts with (the same text as Tools/prefix.txt, which the training data is built from).
    public static var prefix: String {
        "<start_of_turn>developer\nYou are a model that can do function calling with the following functions: "
            + toolNames.joined(separator: ", ") + "<end_of_turn>\n"
    }

    /// The format FunctionGemma was trained on: user turn in, calls out.
    public static func userTurn(_ text: String) -> String {
        "<start_of_turn>user\n\(text)<end_of_turn>\n<start_of_turn>model\n"
    }

    /// Reads every `<start_function_call>call:name{key:<escape>value<escape>,n:30}<end_function_call>` in the
    /// model's output, in order. Anything else in the output is ignored.
    public static func parse(_ output: String) -> [ToolCall] {
        var calls: [ToolCall] = []
        var rest = output[...]
        while let start = rest.range(of: "<start_function_call>call:") {
            let after = rest[start.upperBound...]
            guard let brace = after.firstIndex(of: "{") else { break }
            let name = after[..<brace].trimmingCharacters(in: .whitespaces)
            // A malformed call (no braces before the end marker) is skipped, not trusted.
            if let end = after.range(of: "<end_function_call>"), end.lowerBound < brace {
                rest = after[end.upperBound...]
                continue
            }
            let inside = after[after.index(after: brace)...]
            let bodyEnd = inside.range(of: "}<end_function_call>") ?? inside.range(of: "<end_function_call>")
            let body = inside[..<(bodyEnd?.lowerBound ?? inside.endIndex)]
            calls.append(ToolCall(name: name, args: arguments(String(body))))
            guard let bodyEnd else { break }
            rest = after[bodyEnd.upperBound...]
        }
        return calls
    }

    /// `key:<escape>text, with commas<escape>,other:30` → ["key": "text, with commas", "other": "30"]
    static func arguments(_ body: String) -> [String: String] {
        var out: [String: String] = [:]
        var s = body[...]
        let escape = "<escape>"
        while !s.isEmpty {
            guard let colon = s.firstIndex(of: ":") else { break }
            let key = s[..<colon].trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
            s = s[s.index(after: colon)...]
            let value: String
            if s.hasPrefix(escape) {
                s = s.dropFirst(escape.count)
                if let end = s.range(of: escape) {
                    value = String(s[..<end.lowerBound])
                    s = s[end.upperBound...]
                } else {
                    value = String(s)
                    s = s[s.endIndex...]
                }
            } else {
                let end = s.firstIndex(of: ",") ?? s.endIndex
                value = s[..<end].trimmingCharacters(in: CharacterSet(charactersIn: " }"))
                s = s[end...]
            }
            if !key.isEmpty { out[key] = value }
            if s.hasPrefix(",") { s = s.dropFirst() }
        }
        return out
    }

    /// Whether two calls mean the same thing: same tool, same arguments ignoring capitals and punctuation.
    /// ("open Claude" may come back as an app or a website; the app tries both, so both count.)
    public func matches(_ other: ToolCall) -> Bool {
        func norm(_ s: String) -> String {
            s.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }.split(separator: " ").joined(separator: " ")
        }
        let opens: Set<String> = ["open_app", "open_website"]
        if opens.contains(name), opens.contains(other.name) {
            return norm(args["name"] ?? args["site"] ?? "") == norm(other.args["name"] ?? other.args["site"] ?? "-")
        }
        guard name == other.name, Set(args.keys) == Set(other.args.keys) else { return false }
        return args.allSatisfy { norm($0.value) == norm(other.args[$0.key] ?? "") }
    }
}
