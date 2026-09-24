import AppKit
import EvooCore

/// Notices how the user edits what Evoo just typed, so Evoo can learn from it (see `EditLearner`).
///
/// Right after pasting, it notes the text field's contents. It looks again when the user presses Return
/// (usually "send"), starts the next dictation, or after 30 seconds — whichever comes first — and
/// compares only the part Evoo typed. Nothing is stored except learned words and habit counts.
@MainActor
final class EditWatcher {
    private struct Pending {
        let app: String
        let field: AXUIElement
        let inserted: String
        let before: String
    }

    var onLessons: ((_ lessons: [EditLearner.Lesson], _ app: String) -> Void)?
    private var pending: Pending?
    private var timer: Task<Void, Never>?

    func didInsert(_ text: String, app: String?) {
        observe() // finish any earlier dictation first
        guard let app, let field = ScreenText.focusedField(), let before = ScreenText.value(of: field),
              before.contains(text) else { return }
        pending = Pending(app: app, field: field, inserted: text, before: before)
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            self?.observe()
        }
    }

    /// Compares the field now with what Evoo typed, and reports what was learned.
    func observe() {
        guard let p = pending else { return }
        pending = nil
        timer?.cancel()
        guard let after = ScreenText.value(of: p.field), !after.isEmpty,
              let range = p.before.range(of: p.inserted, options: .backwards) else { return }
        let prefix = String(p.before[..<range.lowerBound])
        guard after.hasPrefix(prefix) else { return } // the text before ours changed too: too ambiguous
        var edited = String(after.dropFirst(prefix.count))
        let suffix = String(p.before[range.upperBound...])
        if !suffix.isEmpty, edited.hasSuffix(suffix) { edited = String(edited.dropLast(suffix.count)) }
        let lessons = EditLearner.lessons(inserted: p.inserted, edited: edited)
        if !lessons.isEmpty { onLessons?(lessons, p.app) }
    }
}
