import AppKit
import EvooCore
import EvooSpeech
import SwiftUI

/// Evoo's main window (opened from the Dock icon or the menu bar): Home with your numbers and recent
/// dictations, plus History, Dictionary, Class Notes and Settings in one place.
struct MainWindowView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var settings: AppSettings
    let openClassNotes: () -> Void
    @State private var page: Page? = .home

    enum Page: String, CaseIterable, Identifiable {
        case home = "Home", history = "History", dictionary = "Dictionary", classNotes = "Class Notes", settings = "Settings"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .home: "house"
            case .history: "clock.arrow.circlepath"
            case .dictionary: "character.book.closed"
            case .classNotes: "graduationcap"
            case .settings: "gearshape"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.line).frame(width: 1)
            Group {
                switch page ?? .home {
                case .home: HomeView(controller: controller, settings: settings, history: .shared, go: { page = $0 },
                                     openClassNotes: openClassNotes)
                case .history: HistoryView(history: .shared, notes: .notes, query: .shared)
                case .dictionary: DictionaryView(settings: settings)
                case .classNotes: ClassNotesHome(open: openClassNotes)
                case .settings:
                    ScrollView {
                        SettingsView(controller: controller, settings: settings, permissions: controller.permissions)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
        }
        .foregroundStyle(Theme.ink)
        .frame(minWidth: 860, minHeight: 600)
    }

    /// Like the website's nav: quiet, with a soft grey highlight for the current page (no system blue).
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 26, height: 26)
                Text("Evoo").font(.system(size: 17, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.top, 34)
            .padding(.bottom, 18)
            ForEach(Page.allCases) { p in
                Button {
                    page = p
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: p.icon).frame(width: 18)
                        Text(p.rawValue)
                        Spacer()
                    }
                    .font(.system(size: 14, weight: page == p ? .semibold : .regular))
                    .foregroundStyle(page == p ? Theme.ink : Theme.ink2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(page == p ? Color.white : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(page == p ? Theme.line : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(controller.permissions.allGranted ? Theme.green : Color.orange).frame(width: 7, height: 7)
                Text(controller.permissions.allGranted ? "Ready — hold fn" : "Needs permissions")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(10)
        }
        .padding(10)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(Theme.soft)
    }
}

// MARK: - Home

private struct HomeView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: DictationHistory
    let go: (MainWindowView.Page) -> Void
    let openClassNotes: () -> Void
    @State private var copied: UUID?

    private var words: Int { settings.wordsDictated }
    private var minutesSpoken: Double { settings.secondsDictated / 60 }
    /// Typing at 40 words a minute vs what it took to say it.
    private var minutesSaved: Double { max(0, Double(words) / 40 - minutesSpoken) }
    private var wpm: Int { minutesSpoken > 0.5 ? Int(Double(words) / minutesSpoken) : 0 }
    private var thisWeek: Int {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return history.entries.filter { $0.date >= start }.map { $0.text.split(whereSeparator: \.isWhitespace).count }.reduce(0, +)
    }

    private var streak: Int {
        let days = Set(history.entries.map { Calendar.current.startOfDay(for: $0.date) })
        var day = Calendar.current.startOfDay(for: Date())
        if !days.contains(day) { day = Calendar.current.date(byAdding: .day, value: -1, to: day)! }
        var n = 0
        while days.contains(day) {
            n += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        }
        return n
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    Stat(value: words.formatted(), label: "words dictated", icon: "text.word.spacing")
                    Stat(value: settings.dictationCount.formatted(), label: "dictations", icon: "waveform")
                    Stat(value: wpm > 0 ? "\(wpm)" : "–", label: "words a minute, spoken", icon: "speedometer")
                    Stat(value: saved, label: "saved vs typing", icon: "clock.badge.checkmark")
                    Stat(value: thisWeek.formatted(), label: "words this week", icon: "calendar")
                    Stat(value: streak > 0 ? "\(streak) day\(streak == 1 ? "" : "s")" : "–", label: "streak", icon: "flame")
                }
                recent
                actions
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private var saved: String {
        minutesSaved >= 60 ? String(format: "%.1f h", minutesSaved / 60) : "\(Int(minutesSaved.rounded())) min"
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting).font(.system(size: 28, weight: .bold))
                HStack(spacing: 6) {
                    Text("Hold").foregroundStyle(.secondary)
                    Text("fn").font(.system(.body, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.soft))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.line))
                    Text("in any app, speak, and let go.").foregroundStyle(.secondary)
                }
                Text("Add ⌃ (fn + Control) to give a command instead: “close the tab and switch to Claude”.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if Features.multilingual {
                Picker("Language", selection: $settings.language) {
                    ForEach(Features.quickLanguages, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 200)
            }
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent").font(.headline)
                Spacer()
                Button("See all") { go(.history) }.buttonStyle(.link)
            }
            if history.entries.isEmpty {
                Text("Your dictations will show up here.").foregroundStyle(.secondary)
            }
            ForEach(Array(history.entries.prefix(6))) { e in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(e.text).lineLimit(2).textSelection(.enabled)
                        Text(e.date.formatted(.relative(presentation: .named)) + (e.app.map { " · " + EditWatcher.appName($0) } ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(copied == e.id ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(e.text, forType: .string)
                        copied = e.id
                    }
                }
                .padding(12)
                .card(radius: 10)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Action(title: "Class Notes", detail: "Notes from a lecture", icon: "graduationcap", run: openClassNotes)
            Action(title: "Dictionary", detail: "Names Evoo knows", icon: "character.book.closed") { go(.dictionary) }
            Action(title: "Settings", detail: "Polish, mic, pill, Hinglish", icon: "gearshape") { go(.settings) }
        }
    }
}

private struct Stat: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(Theme.ink2)
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.callout).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }
}

private struct Action: View {
    let title: String
    let detail: String
    let icon: String
    let run: () -> Void

    var body: some View {
        Button(action: run) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(Theme.ink).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dictionary

private struct DictionaryView: View {
    @ObservedObject var settings: AppSettings
    @State private var newWord = ""
    @State private var filter = ""

    private var words: [String] {
        let all = settings.personalWords.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return filter.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dictionary").font(.system(size: 26, weight: .bold))
            Text("Names and words Evoo spells your way — added by you, learned from your corrections, or seen on your screen.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("Add a name or word, e.g. Divya, Kubernetes", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            TextField("Search", text: $filter).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
            List {
                ForEach(words, id: \.self) { w in
                    HStack {
                        Text(w)
                        if settings.screenLearned.contains(w) {
                            Text("from screen").font(.caption2).foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        }
                        Spacer()
                        Button {
                            settings.personalWords.removeAll { $0 == w }
                            settings.screenLearned.removeAll { $0 == w }
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.inset)
            Text("\(settings.personalWords.count) words").font(.caption).foregroundStyle(.secondary)
        }
        .padding(28)
    }

    private func add() {
        let w = newWord.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty, !settings.personalWords.contains(w) else { return }
        settings.personalWords.append(w)
        newWord = ""
    }
}

// MARK: - Class Notes

private struct ClassNotesHome: View {
    let open: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "graduationcap.fill").font(.system(size: 44)).foregroundStyle(Theme.ink)
            Text("Class Notes").font(.system(size: 26, weight: .bold))
            Text("Evoo listens to a lecture and jots down what matters — formulas, definitions, what's on the exam — then gives you a study sheet, flashcards and Q&A.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            Button("Open Class Notes", action: open).buttonStyle(.borderedProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }
}
