import Foundation

/// Something a voice command can open or search: an installed app, a website, or a service with a search URL.
public struct AppTarget: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name.lowercased() }
    public var name: String
    /// Other names people say ("gmail" for Google Mail, "vs code" for Visual Studio Code).
    public var aliases: [String] = []
    /// Installed Mac app to open.
    public var bundleID: String?
    /// Website to open when there's no app (or instead of it).
    public var url: String?
    /// Search/ask link with `{query}`, e.g. "https://www.google.com/search?q={query}".
    public var searchURL: String?

    public init(name: String, aliases: [String] = [], bundleID: String? = nil, url: String? = nil,
                searchURL: String? = nil)
    {
        self.name = name
        self.aliases = aliases
        self.bundleID = bundleID
        self.url = url
        self.searchURL = searchURL
    }

    var spokenNames: [String] { ([name] + aliases).map { $0.lowercased() } }
}

public enum AppCommand: Equatable, Sendable {
    case open(AppTarget)
    case search(AppTarget, query: String)
    case openURL(URL)
}

/// Voice commands that act on apps instead of typing:
///   "open Slack", "switch to Chrome", "open github.com"
///   "search Google for flights to Delhi", "YouTube lo-fi music", "ask ChatGPT how tides work"
///   "new Google doc", "new email about the invoice"
/// Only a dictation that is entirely a command, naming a known app or site, counts.
public enum AppCommands {
    /// Web services that work without installing anything.
    public static let builtIn: [AppTarget] = [
        .init(name: "Google", url: "https://www.google.com", searchURL: "https://www.google.com/search?q={query}"),
        .init(name: "YouTube", url: "https://www.youtube.com", searchURL: "https://www.youtube.com/results?search_query={query}"),
        .init(name: "ChatGPT", aliases: ["chat gpt"], url: "https://chatgpt.com", searchURL: "https://chatgpt.com/?q={query}"),
        .init(name: "Claude", url: "https://claude.ai", searchURL: "https://claude.ai/new?q={query}"),
        .init(name: "Perplexity", url: "https://www.perplexity.ai", searchURL: "https://www.perplexity.ai/search?q={query}"),
        .init(name: "Gmail", aliases: ["google mail"], url: "https://mail.google.com",
              searchURL: "https://mail.google.com/mail/u/0/#search/{query}"),
        .init(name: "Google Calendar", url: "https://calendar.google.com"),
        .init(name: "Google Drive", aliases: ["drive"], url: "https://drive.google.com",
              searchURL: "https://drive.google.com/drive/search?q={query}"),
        .init(name: "Google Maps", aliases: ["maps"], url: "https://maps.google.com",
              searchURL: "https://www.google.com/maps/search/{query}"),
        .init(name: "WhatsApp", aliases: ["whatsapp web"], url: "https://web.whatsapp.com"),
        .init(name: "Amazon", url: "https://www.amazon.com", searchURL: "https://www.amazon.com/s?k={query}"),
        .init(name: "Wikipedia", url: "https://en.wikipedia.org",
              searchURL: "https://en.wikipedia.org/w/index.php?search={query}"),
        .init(name: "GitHub", url: "https://github.com", searchURL: "https://github.com/search?q={query}"),
        .init(name: "LinkedIn", url: "https://www.linkedin.com",
              searchURL: "https://www.linkedin.com/search/results/all/?keywords={query}"),
        .init(name: "X", aliases: ["twitter"], url: "https://x.com", searchURL: "https://x.com/search?q={query}"),
        .init(name: "Reddit", url: "https://www.reddit.com", searchURL: "https://www.reddit.com/search/?q={query}"),
        .init(name: "Spotify", url: "https://open.spotify.com", searchURL: "https://open.spotify.com/search/{query}"),
        .init(name: "Netflix", url: "https://www.netflix.com", searchURL: "https://www.netflix.com/search?q={query}"),
        .init(name: "Notion", url: "https://www.notion.so"),
        .init(name: "Figma", url: "https://www.figma.com"),
    ]

    /// "new Google doc" & friends: things to create.
    static let creators: [(pattern: String, url: String)] = [
        (#"(?:google )?doc(?:ument)?"#, "https://docs.new"),
        (#"(?:google )?(?:sheet|spreadsheet)"#, "https://sheets.new"),
        (#"(?:google )?(?:slides?|slide deck|presentation)"#, "https://slides.new"),
        (#"(?:google )?form"#, "https://forms.new"),
        (#"(?:meeting|calendar event|event)"#, "https://calendar.google.com/calendar/r/eventedit"),
        (#"(?:email|mail|gmail)"#, "mailto:"),
        (#"(?:chat ?gpt chat|chat)"#, "https://chatgpt.com"),
    ]

    public static func parse(_ dictation: String, targets: [AppTarget]) -> AppCommand? {
        let s = dictation.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".!?")))
        guard s.count <= 200 else { return nil }
        func match(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: "^(?i)(?:please |hey evoo,? )?" + pattern + "$"),
                  let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
            return (0 ..< m.numberOfRanges).map { Range(m.range(at: $0), in: s).map { String(s[$0]) } ?? "" }
        }
        func target(named spoken: String) -> AppTarget? {
            let n = normalize(spoken)
            return targets.first { $0.spokenNames.map(normalize).contains(n) }
        }

        // "new Google doc", "new email about the invoice"
        if let m = match(#"(?:create|start|open|make)?\s*(?:a )?new (.+?)(?: about (.+))?"#) {
            for (pattern, url) in creators where m[1].range(of: "^(?i)" + pattern + "$", options: .regularExpression) != nil {
                if url == "mailto:" {
                    let subject = m[2].addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    return URL(string: m[2].isEmpty ? "mailto:" : "mailto:?subject=\(subject)").map(AppCommand.openURL)
                }
                return URL(string: url).map(AppCommand.openURL)
            }
        }
        // "search Google for X", "search for X on YouTube", "look up X on Wikipedia"
        if let m = match(#"(?:search|look up|find|look for)(?: on| in)? (.+?) for (.+)"#), let t = target(named: m[1]),
           t.searchURL != nil
        {
            return .search(t, query: m[2])
        }
        if let m = match(#"(?:search|look up|find|look for)(?: for)? (.+) (?:on|in|using) (.+)"#), let t = target(named: m[2]),
           t.searchURL != nil
        {
            return .search(t, query: m[1])
        }
        // "ask ChatGPT X", "google X", "YouTube X"
        if let m = match(#"(?:ask|google|youtube|search) (.+)"#) {
            let lower = s.lowercased()
            if lower.hasPrefix("google ") || lower.hasPrefix("please google ") {
                return targets.first { $0.name == "Google" }.map { .search($0, query: m[1]) }
            }
            // "ask ChatGPT how tides work": the longest known name at the start is the target.
            for t in targets where t.searchURL != nil {
                for name in t.spokenNames.sorted(by: { $0.count > $1.count }) where m[1].lowercased().hasPrefix(name + " ") {
                    let query = String(m[1].dropFirst(name.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,:"))
                    if !query.isEmpty { return .search(t, query: query) }
                }
            }
        }
        let verbs = #"(?:open|launch|start|switch to|go to|bring up|show me|pull up)"#
        // "open github.com", "go to evoo dot app" — checked before " app" is trimmed as a suffix below.
        if let m = match(verbs + #" (?:the )?(.+)"#) {
            let site = m[1].lowercased().replacingOccurrences(of: " dot ", with: ".").replacingOccurrences(of: " ", with: "")
            if site.range(of: #"^[a-z0-9-]+(\.[a-z0-9-]+)*\.(com|org|net|io|ai|app|dev|co|in|edu|gov|so|me|tv)(/\S*)?$"#,
                          options: .regularExpression) != nil
            {
                return URL(string: "https://" + site).map(AppCommand.openURL)
            }
        }
        // "open Slack", "switch to Chrome", "open the Notion app"
        if let m = match(verbs + #" (?:the |my )?(.+?)(?: app| application| website)?"#), let t = target(named: m[1]) {
            return .open(t)
        }
        return nil
    }

    /// Where a search goes: the target's search link with the query filled in.
    public static func searchURL(_ target: AppTarget, query: String) -> URL? {
        guard let template = target.searchURL,
              let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#")))
        else { return nil }
        return URL(string: template.replacingOccurrences(of: "{query}", with: q))
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
