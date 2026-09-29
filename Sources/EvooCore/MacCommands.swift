import Foundation

/// A key combination, e.g. ⌘⇧T.
public struct KeyCombo: Equatable, Sendable {
    public var key: String // "t", "return", "left", "f5", …
    public var command = false
    public var shift = false
    public var option = false
    public var control = false

    public init(_ key: String, command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }
}

public enum WindowAction: String, Equatable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf, maximize, center, fullScreen, minimize
}

/// Controlling the Mac by voice. Like every command, it only fires when the whole dictation is the command.
public enum MacCommand: Equatable, Sendable {
    case spotlight(String)
    case runShortcut(String)
    case keys(KeyCombo, name: String)
    case volume(Int)
    case volumeStep(up: Bool)
    case mute(Bool)
    case media(Media)
    case darkMode(Bool)
    case window(WindowAction)
    case click(String)
    case reminder(task: String, due: Date?)
    case event(title: String, start: Date, minutes: Int)
    case note(String)
    case askHistory(String)
    case readAloud
    case stopReading
    case transcribeFile
    case searchClassNotes(String)
    case openClassNotes

    public enum Media: String, Sendable { case playPause, next, previous }
}

public enum MacCommands {
    public static func parse(_ dictation: String, now: Date = Date()) -> MacCommand? {
        let s = dictation.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".!?")))
        guard !s.isEmpty, s.count <= 300 else { return nil }
        func match(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: "^(?i)(?:please |hey evoo,? )?" + pattern + "$"),
                  let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
            return (0 ..< m.numberOfRanges).map { Range(m.range(at: $0), in: s).map { String(s[$0]) } ?? "" }
        }

        // Spotlight: "search my Mac for tax documents", "spotlight quarterly report", "find the file invoice"
        if let m = match(#"(?:search (?:my |the |this )?(?:mac|computer|laptop|files)(?: for)?|spotlight(?: search)?(?: for)?|find (?:the |my )?files? (?:called |named )?)[,:]? (.+)"#) {
            return .spotlight(m[1])
        }
        // Apple Shortcuts: "run shortcut Morning Routine", "run the Morning Routine shortcut"
        if let m = match(#"run (?:the )?shortcut (?:called |named )?(.+)"#) ?? match(#"run (?:the |my )?(.+?) shortcut"#) {
            return .runShortcut(m[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"“” ")))
        }
        // Keys: named actions first, then "press <combo>"
        let lower = s.lowercased()
        if let (combo, name) = namedKeys[lower.replacingOccurrences(of: "please ", with: "")] {
            return .keys(combo, name: name)
        }
        if let m = match(#"(?:press|hit|type) (.+)"#), let combo = combo(m[1]) {
            return .keys(combo, name: m[1])
        }
        // Volume & media
        if let m = match(#"(?:set (?:the )?)?volume (?:to )?(\d{1,3})(?: ?%| percent)?"#), let v = Int(m[1]) {
            return .volume(min(100, v))
        }
        if match(#"(?:turn (?:the )?)?volume up|louder|turn it up"#) != nil { return .volumeStep(up: true) }
        if match(#"(?:turn (?:the )?)?volume down|quieter|softer|turn it down"#) != nil { return .volumeStep(up: false) }
        if match(#"mute(?: (?:the )?(?:sound|volume|mac|audio))?"#) != nil { return .mute(true) }
        if match(#"unmute(?: (?:the )?(?:sound|volume|mac|audio))?"#) != nil { return .mute(false) }
        if match(#"(?:play|pause|resume)(?: (?:the )?(?:music|song|video|media))?|play pause"#) != nil { return .media(.playPause) }
        if match(#"(?:next|skip)(?: (?:the )?)?(?:song|track)|skip (?:this|it)"#) != nil { return .media(.next) }
        if match(#"previous (?:song|track)|(?:go )?back a (?:song|track)"#) != nil { return .media(.previous) }
        if let m = match(#"(?:turn on |switch to |enable )?(dark|light) mode(?: on)?"#) { return .darkMode(m[1].lowercased() == "dark") }
        if match(#"(?:turn off|disable) dark mode"#) != nil { return .darkMode(false) }
        // Windows: "move this to the left half", "maximize this window", "full screen"
        if let m = match(#"(?:move|snap|put) (?:this|the|this window|the window|it) (?:to )?(?:the )?(left|right|top|bottom) (?:half|side)"#) {
            return .window(WindowAction(rawValue: m[1].lowercased() + "Half")!)
        }
        if match(#"(?:maximi[sz]e|make (?:this|it) bigger)(?: (?:this|the) window)?"#) != nil { return .window(.maximize) }
        if match(#"(?:center|centre) (?:this|the|this window|the window|it)"#) != nil { return .window(.center) }
        if match(#"(?:go |make (?:this|it) |enter )?full ?screen"#) != nil { return .window(.fullScreen) }
        if match(#"minimi[sz]e(?: (?:this|the) window|(?: this| it))?"#) != nil { return .window(.minimize) }
        // Click a button by its name: "click Send", "press the Reply all button"
        if let m = match(#"(?:click|tap|press) (?:on )?(?:the )?(.+?)(?: button| link| tab)?"#), combo(m[1]) == nil,
           m[1].count >= 2, m[1].split(separator: " ").count <= 4
        {
            return .click(m[1])
        }
        // Reminders & calendar
        if let m = match(#"remind me (?:to |about )?(.+)"#) {
            let (task, date) = splitDate(m[1], now: now)
            return .reminder(task: capitalizedFirst(task), due: date)
        }
        if let m = match(#"(?:schedule|add|create|book|set up|put)(?: an?| my)? (.+?)(?: (?:to|on|in) (?:my |the )?calendar)?"#) {
            let (rest, date) = splitDate(m[1], now: now)
            if let date {
                var title = rest.replacingOccurrences(of: #"(?i)^(?:a |an )?(?:event |meeting )?(?:called |for )?"#, with: "",
                                                      options: .regularExpression)
                var minutes = defaultMinutes(for: title)
                if let d = title.range(of: #"(?i)\s*for (?:an? |one )?(\d+ )?(hour|hours|minutes|mins)"#, options: .regularExpression) {
                    let spec = String(title[d]).lowercased()
                    let n = Int(spec.filter(\.isNumber)) ?? 1
                    minutes = spec.contains("hour") ? n * 60 : n
                    title.removeSubrange(d)
                }
                return .event(title: capitalizedFirst(title.trimmingCharacters(in: .whitespaces)), start: date, minutes: minutes)
            }
        }
        // Class notes: "search note Bayes theorem", "search my class notes for variance", "start class notes"
        if let m = match(#"(?:search|find|look up)(?: in)? (?:my |the )?(?:class |lecture )?notes?(?: for| about)? (.+)"#) {
            return .searchClassNotes(m[1])
        }
        if match(#"(?:start|open|take|begin)(?: a| my)? (?:class|lecture)(?: notes| mode)?|class (?:notes|mode)"#) != nil {
            return .openClassNotes
        }
        // Notes & asking your history
        if let m = match(#"(?:note(?: to self)?|take a note|make a note|save a note|jot down)[,:]? (?:that )?(.+)"#) {
            return .note(capitalizedFirst(m[1]))
        }
        if let m = match(#"(?:what did I (?:say|write|dictate|note|tell \w+)|find (?:my |the )?(?:note|dictation|message)s?|search my (?:history|dictations)(?: for)?) (?:about |on |for )?(.+)"#) {
            return .askHistory(m[1])
        }
        // Audio
        if match(#"read (?:this|that|it|the selection|the selected text)?\s*(?:aloud|out loud)|read (?:this|that|it) to me|read aloud"#) != nil {
            return .readAloud
        }
        if match(#"stop (?:reading|talking|speaking)"#) != nil { return .stopReading }
        if match(#"transcribe (?:a |an |this )?(?:file|recording|audio|video)"#) != nil { return .transcribeFile }
        return nil
    }

    // MARK: - Keys

    static let namedKeys: [String: (KeyCombo, String)] = [
        "new tab": (KeyCombo("t", command: true), "New tab"),
        "close tab": (KeyCombo("w", command: true), "Close tab"),
        "close this tab": (KeyCombo("w", command: true), "Close tab"),
        "reopen tab": (KeyCombo("t", command: true, shift: true), "Reopen tab"),
        "reopen closed tab": (KeyCombo("t", command: true, shift: true), "Reopen tab"),
        "reopen the last tab": (KeyCombo("t", command: true, shift: true), "Reopen tab"),
        "next tab": (KeyCombo("tab", control: true), "Next tab"),
        "previous tab": (KeyCombo("tab", shift: true, control: true), "Previous tab"),
        "new window": (KeyCombo("n", command: true), "New window"),
        "close window": (KeyCombo("w", command: true, shift: true), "Close window"),
        "refresh": (KeyCombo("r", command: true), "Refresh"),
        "reload": (KeyCombo("r", command: true), "Refresh"),
        "refresh the page": (KeyCombo("r", command: true), "Refresh"),
        "reload the page": (KeyCombo("r", command: true), "Refresh"),
        "select all": (KeyCombo("a", command: true), "Select all"),
        "copy": (KeyCombo("c", command: true), "Copy"),
        "copy that": (KeyCombo("c", command: true), "Copy"),
        "cut": (KeyCombo("x", command: true), "Cut"),
        "cut that": (KeyCombo("x", command: true), "Cut"),
        "paste": (KeyCombo("v", command: true), "Paste"),
        "paste that": (KeyCombo("v", command: true), "Paste"),
        "redo": (KeyCombo("z", command: true, shift: true), "Redo"),
        "save": (KeyCombo("s", command: true), "Save"),
        "save this": (KeyCombo("s", command: true), "Save"),
        "save the file": (KeyCombo("s", command: true), "Save"),
        "find": (KeyCombo("f", command: true), "Find"),
        "find on page": (KeyCombo("f", command: true), "Find"),
        "print": (KeyCombo("p", command: true), "Print"),
        "print this": (KeyCombo("p", command: true), "Print"),
        "quit": (KeyCombo("q", command: true), "Quit"),
        "quit this app": (KeyCombo("q", command: true), "Quit"),
        "hide this app": (KeyCombo("h", command: true), "Hide"),
        "go back": (KeyCombo("[", command: true), "Back"),
        "go forward": (KeyCombo("]", command: true), "Forward"),
        "zoom in": (KeyCombo("=", command: true), "Zoom in"),
        "zoom out": (KeyCombo("-", command: true), "Zoom out"),
        "scroll down": (KeyCombo("pagedown"), "Scroll down"),
        "page down": (KeyCombo("pagedown"), "Scroll down"),
        "scroll up": (KeyCombo("pageup"), "Scroll up"),
        "page up": (KeyCombo("pageup"), "Scroll up"),
        "go to the top": (KeyCombo("up", command: true), "Top"),
        "go to the bottom": (KeyCombo("down", command: true), "Bottom"),
        "take a screenshot": (KeyCombo("4", command: true, shift: true), "Screenshot"),
        "screenshot": (KeyCombo("4", command: true, shift: true), "Screenshot"),
        "lock screen": (KeyCombo("q", command: true, control: true), "Lock screen"),
        "lock my mac": (KeyCombo("q", command: true, control: true), "Lock screen"),
        "open spotlight": (KeyCombo("space", command: true), "Spotlight"),
        "switch app": (KeyCombo("tab", command: true), "Switch app"),
    ]

    static let keyNames: [String: String] = [
        "enter": "return", "return": "return", "escape": "escape", "esc": "escape", "tab": "tab", "space": "space",
        "spacebar": "space", "delete": "delete", "backspace": "delete", "forward delete": "forwarddelete",
        "up": "up", "down": "down", "left": "left", "right": "right", "up arrow": "up", "down arrow": "down",
        "left arrow": "left", "right arrow": "right", "page up": "pageup", "page down": "pagedown", "home": "home",
        "end": "end", "comma": ",", "period": ".", "dot": ".", "slash": "/", "minus": "-", "equals": "=", "plus": "=",
    ]

    /// "command shift t", "control option delete", "enter", "f5" → a key combo.
    static func combo(_ spoken: String) -> KeyCombo? {
        let cleaned: String = spoken.lowercased().replacingOccurrences(of: "+", with: " ")
            .replacingOccurrences(of: #"[,.]"#, with: " ", options: .regularExpression)
        let fillers: Set<String> = ["and", "the", "key"]
        var words: [String] = cleaned.split(separator: " ").map { String($0) }.filter { !fillers.contains($0) }
        var combo = KeyCombo("")
        while let w = words.first, ["command", "cmd", "shift", "option", "alt", "control", "ctrl"].contains(w) {
            switch w {
            case "command", "cmd": combo.command = true
            case "shift": combo.shift = true
            case "option", "alt": combo.option = true
            default: combo.control = true
            }
            words.removeFirst()
        }
        let rest = words.joined(separator: " ")
        if let named = keyNames[rest] {
            combo.key = named
        } else if rest.count == 1, let c = rest.first, c.isLetter || c.isNumber {
            combo.key = rest
        } else if rest.range(of: #"^f(1[0-2]|[1-9])$"#, options: String.CompareOptions.regularExpression) != nil {
            combo.key = rest
        } else {
            return nil
        }
        // A lone letter isn't a key press ("press A" is too ambiguous) unless a modifier is held.
        if combo.key.count == 1, combo.key.first!.isLetter, !(combo.command || combo.control || combo.option) { return nil }
        return combo
    }

    // MARK: - Dates

    /// Splits "call Divya tomorrow at 5 PM" into ("call Divya", tomorrow 17:00).
    static func splitDate(_ text: String, now: Date) -> (String, Date?) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let m = detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let date = m.date, let r = Range(m.range, in: text)
        else { return (text, nil) }
        var rest = text
        rest.removeSubrange(r)
        rest = rest.replacingOccurrences(of: #"(?i)\s+(?:on|at|by|for|in)\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        // "tomorrow" with no time means 9 AM, not whatever time it is now.
        var due = date
        let phrase = String(text[r]).lowercased()
        let saidATime = phrase.range(of: #"\d|noon|midnight|morning|afternoon|evening|night|o'?clock|minute|hour"#,
                                     options: .regularExpression) != nil
        if !saidATime {
            due = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        }
        _ = now
        return (rest, due)
    }

    static func defaultMinutes(for title: String) -> Int {
        let t = title.lowercased()
        if t.contains("lunch") || t.contains("dinner") || t.contains("breakfast") { return 60 }
        return 30
    }

    static func capitalizedFirst(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
    }
}
