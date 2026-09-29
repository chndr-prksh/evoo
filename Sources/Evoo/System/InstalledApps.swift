import AppKit
import EvooCore

/// Every app installed on this Mac, as voice-command targets ("open Slack"), merged with the built-in web
/// services and the user's own additions. Scanned once in the background at launch.
@MainActor
final class InstalledApps: ObservableObject {
    static let shared = InstalledApps()

    @Published private(set) var apps: [AppTarget] = []

    /// What people actually say for some apps.
    nonisolated private static let nicknames: [String: [String]] = [
        "Google Chrome": ["chrome"], "Visual Studio Code": ["vs code", "vscode", "code"],
        "Microsoft Teams": ["teams"], "Microsoft Word": ["word"], "Microsoft Excel": ["excel"],
        "Microsoft PowerPoint": ["powerpoint"], "Microsoft Outlook": ["outlook"], "zoom.us": ["zoom"],
        "System Settings": ["settings", "system preferences"], "App Store": ["app store"],
        "Activity Monitor": ["activity monitor"], "Brave Browser": ["brave"], "Microsoft Edge": ["edge"],
        "Firefox": ["firefox"], "Arc": ["arc browser"], "iTerm": ["iterm"], "Photo Booth": ["photo booth"],
    ]

    func scan() {
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            let folders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                           "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
            var found: [AppTarget] = []
            for folder in folders {
                for item in (try? fm.contentsOfDirectory(atPath: folder)) ?? [] where item.hasSuffix(".app") {
                    let url = URL(fileURLWithPath: folder).appendingPathComponent(item)
                    guard let id = Bundle(url: url)?.bundleIdentifier, id != "app.evoo.Evoo" else { continue }
                    let name = String(item.dropLast(4))
                    found.append(AppTarget(name: name, aliases: Self.nicknames[name] ?? [], bundleID: id))
                }
            }
            let sorted = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            await MainActor.run { InstalledApps.shared.apps = sorted }
        }
    }

    /// The user's additions first (they win), then installed apps, then web services. An installed app with the
    /// same name as a web service (Notion, Spotify, WhatsApp) opens the app but keeps the service's search link.
    func targets(custom: [AppTarget]) -> [AppTarget] {
        var byName: [String: AppTarget] = [:]
        for t in Websites.all + AppCommands.builtIn { byName[t.id] = t }
        for app in apps {
            if var web = byName[app.id] {
                web.bundleID = app.bundleID
                web.aliases += app.aliases
                byName[app.id] = web
            } else {
                byName[app.id] = app
            }
        }
        for t in custom where !t.name.trimmingCharacters(in: .whitespaces).isEmpty { byName[t.id] = t }
        return Array(byName.values)
    }

    /// Opens or searches; returns what to tell the user, or nil if it couldn't.
    func run(_ command: AppCommand) -> String? {
        switch command {
        case let .open(target):
            if let id = target.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
                return "Opening \(target.name)"
            }
            guard let site = target.url.flatMap(URL.init(string:)) else { return nil }
            NSWorkspace.shared.open(site)
            return "Opening \(target.name)"
        case let .search(target, query):
            guard let url = AppCommands.searchURL(target, query: query) else { return nil }
            NSWorkspace.shared.open(url)
            return "Searching \(target.name)"
        case let .openIn(url, browser):
            guard let id = browser.bundleID, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                return nil
            }
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            return "Opening \(url.host ?? "site") in \(browser.name)"
        case let .openURL(url):
            NSWorkspace.shared.open(url)
            return "Opening \(url.host ?? "new \(url.scheme ?? "item")")"
        }
    }
}
