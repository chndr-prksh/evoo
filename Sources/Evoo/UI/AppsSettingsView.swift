import AppKit
import EvooCore
import SwiftUI

/// Settings → Apps: voice commands for apps, the services Evoo knows, and the user's own additions.
struct AppsSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var installed: InstalledApps
    @State private var filter = ""

    var body: some View {
        Form {
            Section {
                Toggle("Voice commands", isOn: $settings.appCommands)
                Text("Say the whole thing as one dictation — anything else is typed as usual.")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Everything you can say") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Self.examples, id: \.0) { group, lines in
                            Text(group).font(.caption.bold())
                            Text(lines).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Your apps and sites") {
                Text("Add an app or website that isn't below. A search link with {query} lets you say “search <name> for …” — e.g. https://wiki.mycompany.com/search?q={query}")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(settings.customApps.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Name you'll say", text: $settings.customApps[i].name)
                            Button {
                                settings.customApps.remove(at: i)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        if let id = settings.customApps[i].bundleID {
                            Text("Opens \(EditWatcher.appName(id))").font(.caption).foregroundStyle(.secondary)
                        } else {
                            TextField("Website (https://…)", text: optional($settings.customApps[i].url))
                        }
                        TextField("Search link with {query} (optional)", text: optional($settings.customApps[i].searchURL))
                    }
                    .padding(.vertical, 2)
                }
                HStack {
                    Button("Add app…", action: pickApp)
                    Button("Add website") { settings.customApps.append(AppTarget(name: "", url: "https://")) }
                }
            }

            Section("Built-in web services (\(AppCommands.builtIn.count))") {
                Text(AppCommands.builtIn.map { $0.searchURL != nil ? "\($0.name) 🔍" : $0.name }.joined(separator: " · "))
                    .font(.caption)
                Text("🔍 = you can also search it: “search YouTube for …”, “ask ChatGPT …”.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Installed apps (\(installed.apps.count))") {
                Text("Evoo can open any of these by name — “open …”.").font(.caption).foregroundStyle(.secondary)
                TextField("Filter", text: $filter)
                let shown = installed.apps.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
                ForEach(shown.prefix(200)) { app in
                    HStack {
                        Text(app.name)
                        Spacer()
                        if !app.aliases.isEmpty {
                            Text("also “\(app.aliases.joined(separator: "”, “"))”").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    static let examples: [(String, String)] = [
        ("Apps & web", "“open Slack” · “switch to Chrome” · “open github.com” · “search Google for flights to Delhi” · “ask ChatGPT how tides work” · “YouTube lo-fi music” · “new Google doc” · “new email about the invoice”"),
        ("Your Mac", "“search my Mac for tax documents” (Spotlight) · “run shortcut Morning Routine” · “volume 30” · “mute” · “next song” · “dark mode” · “take a screenshot” · “lock screen”"),
        ("Keys", "“new tab” · “close tab” · “reopen tab” · “refresh” · “select all” · “copy” · “paste” · “save” · “go back” · “scroll down” · “press command shift T” · “press enter”"),
        ("Windows & buttons", "“move this to the left half” · “maximize this window” · “full screen” · “minimize” · “click Send” · “press the Reply all button”"),
        ("Assistant", "“remind me to call Divya tomorrow at 5” · “schedule lunch with Raj Friday at 1 PM” · “note: pricing idea…” · “what did I say about the invoice?”"),
        ("Audio", "“read this aloud” (selected text) · “stop reading” · “transcribe a file”"),
        ("Editing", "“replace Tuesday with Wednesday” · “delete the last sentence” · “make that a list” · “undo that” · “… press enter”"),
    ]

    /// Choose an installed app to add under a name of your choice.
    private func pickApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        settings.customApps.append(AppTarget(name: url.deletingPathExtension().lastPathComponent, bundleID: id))
    }

    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}
