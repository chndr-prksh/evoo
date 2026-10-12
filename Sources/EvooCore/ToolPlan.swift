import Foundation

/// What one tool call (see Tools/tools.json) does on the Mac.
public enum ToolStep: Equatable, Sendable {
    /// Something the voice commands already do: keys, volume, windows, reminders, notes…
    case mac(MacCommand)
    /// Open or search an app or site.
    case app(AppCommand)
    case quitApp(String)
    case typeText(String)
    case brightness(up: Bool)
    /// Writes with the local AI: rewrite the selection, reply to what's on screen, translate.
    case rewrite(String)
    case reply(String)
    case translate(text: String, language: String)
    /// The model decided this isn't a command.
    case nothing
    /// A call Evoo can't carry out; the text says why.
    case unknown(String)
}

public enum ToolPlan {
    /// Turns the model's calls into steps. `targets`: the apps and sites Evoo knows (installed apps included).
    /// `said`: what the person said — a call whose words they never said is refused instead of carried out.
    public static func steps(_ calls: [ToolCall], said: String? = nil, targets: [AppTarget], now: Date = Date()) -> [ToolStep] {
        calls.prefix(CommandChain.maxSteps).map { call in
            if let said, !isGrounded(call, in: said) { return .unknown("Didn't catch that — try saying it another way") }
            return step(call, targets: targets, now: now)
        }
    }

    /// Arguments that are the person's own words (a name, a search, a note) and so must come from what they said.
    static let spokenArguments: Set<String> = ["name", "site", "query", "label", "text", "task", "title", "to", "subject", "body",
                                               "destination", "intent", "instruction", "language", "when"]

    /// A small model sometimes invents an argument ("restaurants in New York" for "restaurants open now").
    /// True when every word of every spoken argument was actually said.
    public static func isGrounded(_ call: ToolCall, in said: String) -> Bool {
        let words = { (s: String) in
            s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        }
        let heard = Set(words(said))
        let squeezed = words(said).joined()
        for (key, value) in call.args where spokenArguments.contains(key) {
            // web_search's site is one of a fixed list ("maps" for "on the map"), not the person's words.
            if call.name == "web_search", key == "site" { continue }
            // "text edit" said, "TextEdit" written: compare without spaces too.
            if squeezed.contains(words(value).joined()) { continue }
            if !words(value).allSatisfy(heard.contains) { return false }
        }
        return true
    }

    public static func step(_ call: ToolCall, targets: [AppTarget], now: Date = Date()) -> ToolStep {
        func text(_ key: String) -> String? {
            let v = call.args[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return v?.isEmpty == false ? v : nil
        }
        func keys(_ combo: KeyCombo, _ name: String) -> ToolStep { .mac(.keys(combo, name: name)) }
        let missing = ToolStep.unknown("Didn't catch what to \(call.name.replacingOccurrences(of: "_", with: " "))")

        switch call.name {
        case "open_app", "open_website":
            guard let name = text("name") ?? text("site") else { return missing }
            if let t = AppCommands.target(named: name, in: targets) { return .app(.open(t)) }
            if let url = website(name) { return .app(.openURL(url)) }
            return .unknown("No app or site called “\(name)”")
        case "quit_app":
            return text("name").map(ToolStep.quitApp) ?? missing
        case "web_search":
            guard let query = text("query") else { return missing }
            let site = text("site") ?? "google"
            let target = AppCommands.target(named: site == "maps" ? "Google Maps" : site, in: targets)
                ?? AppCommands.target(named: "Google", in: AppCommands.builtIn)
            guard let target, target.searchURL != nil else { return .unknown("Can't search \(site)") }
            return .app(.search(target, query: query))
        case "find_file":
            return text("query").map { .mac(.spotlight($0)) } ?? missing
        case "press_keys":
            guard let spoken = text("keys") else { return missing }
            guard let combo = MacCommands.combo(spoken.replacingOccurrences(of: "+", with: " "))
                ?? MacCommands.loneKeys[spoken.lowercased()].map({ KeyCombo($0) })
            else { return .unknown("Unknown key “\(spoken)”") }
            return keys(combo, spoken)
        case "edit":
            guard let action = text("action"), let (combo, name) = edits[action] else { return missing }
            return keys(combo, name)
        case "browser":
            guard let action = text("action"), let (combo, name) = browser[action] else { return missing }
            return keys(combo, name)
        case "scroll":
            guard let direction = text("direction"), let (combo, name) = scrolls[direction] else { return missing }
            return keys(combo, name)
        case "system":
            guard let action = text("action"), let (combo, name) = system[action] else { return missing }
            return keys(combo, name)
        case "set_volume":
            return call.int("percent").map { .mac(.volume(max(0, min(100, $0)))) } ?? missing
        case "change_volume":
            return text("direction").map { .mac(.volumeStep(up: $0 == "up")) } ?? missing
        case "mute":
            return .mac(.mute(text("state") != "off"))
        case "media":
            switch text("action") {
            case "next": return .mac(.media(.next))
            case "previous": return .mac(.media(.previous))
            default: return .mac(.media(.playPause))
            }
        case "brightness":
            return text("direction").map { .brightness(up: $0 == "up") } ?? missing
        case "dark_mode":
            return .mac(.darkMode(text("state") != "off"))
        case "window":
            guard let action = text("action"), let w = windows[action] else { return missing }
            return .mac(.window(w))
        case "click":
            return text("label").map { .mac(.click($0)) } ?? missing
        case "type_text":
            return text("text").map(ToolStep.typeText) ?? missing
        case "add_reminder":
            guard let task = text("task") else { return missing }
            let due = text("when").flatMap { MacCommands.splitDate($0, now: now).1 }
            return .mac(.reminder(task: MacCommands.capitalizedFirst(task), due: due))
        case "add_event":
            guard let title = text("title") else { return missing }
            guard let start = text("when").flatMap({ MacCommands.splitDate($0, now: now).1 }) else {
                return .unknown("When is “\(title)”? Say a day or a time")
            }
            let minutes = call.int("minutes") ?? MacCommands.defaultMinutes(for: title)
            return .mac(.event(title: MacCommands.capitalizedFirst(title), start: start, minutes: minutes))
        case "set_timer":
            // A reminder that goes off in N minutes: it shows up (and rings) on every Apple device.
            guard let minutes = call.int("minutes"), minutes > 0 else { return missing }
            let label = text("label").map(MacCommands.capitalizedFirst) ?? "\(minutes)-minute timer"
            return .mac(.reminder(task: label, due: now.addingTimeInterval(TimeInterval(minutes * 60))))
        case "save_note":
            return text("text").map { .mac(.note(MacCommands.capitalizedFirst($0))) } ?? missing
        case "search_history":
            return text("query").map { .mac(.askHistory($0)) } ?? missing
        case "compose_email":
            // Opens a draft in the mail app. Evoo never sends it.
            var parts = URLComponents()
            parts.scheme = "mailto"
            parts.path = text("to") ?? ""
            let items = [("subject", text("subject")), ("body", text("body"))]
                .compactMap { name, value in value.map { URLQueryItem(name: name, value: MacCommands.capitalizedFirst($0)) } }
            if !items.isEmpty { parts.queryItems = items }
            // Mail apps read "+" in a mailto link as a plus sign, so spaces must be %20.
            parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            return parts.url.map { .app(.openURL($0)) } ?? missing
        case "get_directions":
            guard let place = text("destination") else { return missing }
            var parts = URLComponents(string: "https://maps.apple.com/")!
            parts.queryItems = [URLQueryItem(name: "daddr", value: place)]
            return parts.url.map { .app(.openURL($0)) } ?? missing
        case "rewrite_selection":
            return text("instruction").map(ToolStep.rewrite) ?? missing
        case "reply":
            return text("intent").map(ToolStep.reply) ?? missing
        case "translate":
            guard let said = text("text"), let language = text("language") else { return missing }
            return .translate(text: said, language: language)
        case "read_aloud":
            return .mac(text("action") == "stop" ? .stopReading : .readAloud)
        case "class_notes":
            return .mac(text("query").map(MacCommand.searchClassNotes) ?? .openClassNotes)
        case "run_shortcut":
            return text("name").map { .mac(.runShortcut($0)) } ?? missing
        case "transcribe_file":
            return .mac(.transcribeFile)
        case "no_action":
            return .nothing
        default:
            return .unknown("Evoo can't do “\(call.name)” yet")
        }
    }

    /// What the pill says for a step that needs no result message of its own.
    public static func label(_ call: ToolCall) -> String {
        let name = call.name.replacingOccurrences(of: "_", with: " ")
        let detail = ["name", "site", "query", "action", "direction", "label", "task", "title", "destination", "to"]
            .compactMap { call.args[$0] }.first
        return MacCommands.capitalizedFirst(detail.map { "\(name): \($0.replacingOccurrences(of: "_", with: " "))" } ?? name)
    }

    /// "github.com", "bbc.co.uk" or a bare name like "Hacker News" (→ a search for it, which finds the site).
    static func website(_ name: String) -> URL? {
        let compact = name.lowercased().replacingOccurrences(of: " dot ", with: ".").replacingOccurrences(of: " ", with: "")
        if compact.range(of: #"^(?:https?://)?[a-z0-9-]+(?:\.[a-z0-9-]+)+(?:/\S*)?$"#, options: .regularExpression) != nil {
            return URL(string: compact.hasPrefix("http") ? compact : "https://" + compact)
        }
        return nil
    }

    static let edits: [String: (KeyCombo, String)] = [
        "copy": (KeyCombo("c", command: true), "Copy"), "cut": (KeyCombo("x", command: true), "Cut"),
        "paste": (KeyCombo("v", command: true), "Paste"), "undo": (KeyCombo("z", command: true), "Undo"),
        "redo": (KeyCombo("z", command: true, shift: true), "Redo"),
        "select_all": (KeyCombo("a", command: true), "Select all"), "save": (KeyCombo("s", command: true), "Save"),
        "find": (KeyCombo("f", command: true), "Find"), "bold": (KeyCombo("b", command: true), "Bold"),
        "italic": (KeyCombo("i", command: true), "Italic"), "underline": (KeyCombo("u", command: true), "Underline"),
        "print": (KeyCombo("p", command: true), "Print"),
        "delete_word": (KeyCombo("delete", option: true), "Delete word"),
        "delete_line": (KeyCombo("delete", command: true), "Delete line"),
    ]

    static let browser: [String: (KeyCombo, String)] = [
        "new_tab": (KeyCombo("t", command: true), "New tab"), "close_tab": (KeyCombo("w", command: true), "Close tab"),
        "reopen_tab": (KeyCombo("t", command: true, shift: true), "Reopen tab"),
        "next_tab": (KeyCombo("tab", control: true), "Next tab"),
        "previous_tab": (KeyCombo("tab", shift: true, control: true), "Previous tab"),
        "back": (KeyCombo("[", command: true), "Back"), "forward": (KeyCombo("]", command: true), "Forward"),
        "refresh": (KeyCombo("r", command: true), "Refresh"), "new_window": (KeyCombo("n", command: true), "New window"),
        "close_window": (KeyCombo("w", command: true, shift: true), "Close window"),
        "zoom_in": (KeyCombo("=", command: true), "Zoom in"), "zoom_out": (KeyCombo("-", command: true), "Zoom out"),
    ]

    static let scrolls: [String: (KeyCombo, String)] = [
        "up": (KeyCombo("pageup"), "Scroll up"), "down": (KeyCombo("pagedown"), "Scroll down"),
        "top": (KeyCombo("up", command: true), "Top"), "bottom": (KeyCombo("down", command: true), "Bottom"),
    ]

    static let system: [String: (KeyCombo, String)] = [
        "lock_screen": (KeyCombo("q", command: true, control: true), "Lock screen"),
        "screenshot": (KeyCombo("4", command: true, shift: true), "Screenshot"),
        "mission_control": (KeyCombo("up", control: true), "Mission Control"),
        "show_desktop": (KeyCombo("f11"), "Show desktop"),
    ]

    static let windows: [String: WindowAction] = [
        "left": .leftHalf, "right": .rightHalf, "top": .topHalf, "bottom": .bottomHalf, "maximize": .maximize,
        "center": .center, "full_screen": .fullScreen, "minimize": .minimize,
    ]
}
