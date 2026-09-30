import AppKit
import EvooCore
import os

/// Notices how the user edits what Evoo just typed, so Evoo can learn from it (see `EditLearner`).
///
/// After pasting, it re-reads the text field a few times a second (for up to 30 s) and keeps the latest
/// version that still contains the surrounding text. Chat apps clear the field the moment you press
/// Return, so the comparison uses that last snapshot, taken when the user presses Return, starts the next
/// dictation, or after 30 s. Only the part Evoo typed is compared; nothing is stored except learned words
/// and habit counts.
@MainActor
final class EditWatcher {
    private struct Pending {
        let app: String
        let field: AXUIElement
        let inserted: String
        let prefix: String // field text before the dictation
        let suffix: String // field text after it
        var latest: String // most recent snapshot that still has `prefix`
    }

    var onLessons: ((_ lessons: [EditLearner.Lesson], _ app: String) -> Void)?
    /// What Evoo typed and what the user ended up with (for learning their style).
    var onPair: ((_ app: String, _ inserted: String, _ final: String) -> Void)?
    /// Human-readable result of the last check, for Settings → Learning.
    var onStatus: ((String) -> Void)?

    private let log = Logger(subsystem: "app.evoo", category: "learning")
    private var pending: Pending?
    private var poller: Task<Void, Never>?

    func didInsert(_ text: String, app: String?) {
        observe() // finish any earlier dictation first
        guard let app else { return }
        let name = Self.appName(app)
        guard let field = ScreenText.focusedField() else {
            return report("Couldn't find \(name)'s text box", reason: "no focused field", app: app)
        }
        guard let before = ScreenText.value(of: field) else {
            return report("\(name) doesn't let other apps read its text box, so Evoo can't learn there",
                          reason: "field value not readable", app: app)
        }
        guard let range = before.range(of: text, options: .backwards) else {
            return report("Couldn't find the dictation in \(name)'s text box", reason: "inserted text not found", app: app)
        }
        pending = Pending(app: app, field: field, inserted: text, prefix: String(before[..<range.lowerBound]),
                          suffix: String(before[range.upperBound...]), latest: before)
        poller?.cancel()
        poller = Task { [weak self] in
            for _ in 0 ..< 120 { // 30 s at 4 Hz
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                await self.snapshotInBackground()
            }
            self?.observe()
        }
    }

    private func snapshot() {
        guard let p = pending, let value = ScreenText.value(of: p.field) else { return }
        keep(value, for: p)
    }

    /// Reads the text box off the main thread: in a big Chrome/Notion field one read can take 100+ ms, and
    /// doing it 4× a second on the main thread made the pill and waveform stutter.
    private func snapshotInBackground() async {
        guard let p = pending else { return }
        nonisolated(unsafe) let field = p.field
        let value = await Task.detached(priority: .utility) { ScreenText.value(of: field) }.value
        guard let value, pending?.inserted == p.inserted else { return }
        keep(value, for: p)
    }

    private func keep(_ value: String, for p: Pending) {
        guard !value.isEmpty, value.hasPrefix(p.prefix) else { return }
        pending?.latest = value
    }

    /// `observe()` for the start of a dictation: the last look happens off the main thread.
    func observeInBackground() async {
        await snapshotInBackground()
        compareAndReport()
    }

    /// Compares the last snapshot with what Evoo typed, and reports what was learned.
    func observe() {
        snapshot() // one last look, in case the field still has the text
        compareAndReport()
    }

    private func compareAndReport() {
        guard let p = pending else { return }
        pending = nil
        poller?.cancel()
        var edited = String(p.latest.dropFirst(p.prefix.count))
        if !p.suffix.isEmpty, edited.hasSuffix(p.suffix) { edited = String(edited.dropLast(p.suffix.count)) }
        onPair?(p.app, p.inserted, edited)
        let lessons = EditLearner.lessons(inserted: p.inserted, edited: edited)
        let words = lessons.compactMap { lesson -> String? in
            if case let .word(_, meant) = lesson { meant } else { nil }
        }
        let status = edited == p.inserted ? "No edits to learn from"
            : words.isEmpty ? "Checked your edit — nothing new to learn" : "Learned “\(words.joined(separator: "”, “"))”"
        report(status, reason: "compared \(p.inserted.count) → \(edited.count) chars, \(lessons.count) lessons", app: p.app)
        if !lessons.isEmpty { onLessons?(lessons, p.app) }
    }

    private func report(_ status: String, reason: String, app: String) {
        log.notice("learning[\(app, privacy: .public)]: \(reason, privacy: .public)")
        onStatus?("\(Self.appName(app)): \(status)")
    }

    static func appName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }
}
