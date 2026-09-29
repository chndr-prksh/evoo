import AppKit
import SwiftUI

/// A class's notes as one editable document. The AI types into the end of it word by word while the student can
/// edit anywhere — their changes are kept, and the AI never rewrites what's already there.
@MainActor
final class ClassDocument: NSObject, ObservableObject, NSTextStorageDelegate {
    let storage = NSTextStorage()
    /// Called (debounced) with the full text after any change, to save it.
    var onChange: ((String) -> Void)?
    /// Scrolls the editor to the end when the AI adds text and the student was already at the end.
    var followTail: (() -> Void)?
    var text: String { storage.string }

    private var chunk = 0
    private var streamed = "" // what the AI has typed for the current chunk
    private var separator = "" // the line break(s) put before it
    private var saveTask: Task<Void, Never>?

    init(text: String) {
        super.init()
        storage.delegate = self
        storage.setAttributedString(NSAttributedString(string: text, attributes: NotesStyle.base))
        NotesStyle.apply(to: storage, in: NSRange(location: 0, length: storage.length))
    }

    // MARK: AI writing

    /// Starts a new stretch of AI notes; returns its id for `stream` / `finish`.
    func begin() -> Int {
        chunk += 1
        streamed = ""
        separator = ""
        return chunk
    }

    /// The AI's notes so far for this stretch (the whole text so far, not just the new part).
    func stream(_ partial: String, chunk id: Int) {
        guard id == chunk else { return }
        let partial = partial.replacingOccurrences(of: #"^\s+"#, with: "", options: .regularExpression)
        guard !partial.isEmpty else { return }
        if streamed.isEmpty, separator.isEmpty {
            let current = storage.string
            if !current.isEmpty {
                let wantsGap = partial.hasPrefix("#")
                separator = current.hasSuffix("\n\n") ? "" : current.hasSuffix("\n") ? (wantsGap ? "\n" : "") : (wantsGap ? "\n\n" : "\n")
                append(separator)
            }
        }
        if partial.hasPrefix(streamed) {
            append(String(partial.dropFirst(streamed.count)))
        } else {
            replaceTail(streamed, with: partial)
        }
        streamed = partial
    }

    /// The final, tidied notes for this stretch (replaces what was streamed, if it's still at the end untouched).
    func finish(_ final: String, chunk id: Int) {
        guard id == chunk else { return }
        if streamed.isEmpty, !final.isEmpty {
            stream(final, chunk: id)
        } else if final.isEmpty {
            replaceTail(separator + streamed, with: "")
        } else if final != streamed {
            replaceTail(streamed, with: final)
        }
        streamed = ""
        separator = ""
        chunk += 1
    }

    private func append(_ s: String) {
        guard !s.isEmpty else { return }
        let atEnd = true
        storage.replaceCharacters(in: NSRange(location: storage.length, length: 0),
                                  with: NSAttributedString(string: s, attributes: NotesStyle.base))
        if atEnd { followTail?() }
    }

    private func replaceTail(_ old: String, with new: String) {
        let current = storage.string as NSString
        guard !old.isEmpty, current.hasSuffix(old) else {
            if !new.isEmpty, old.isEmpty { append(new) }
            return
        }
        let len = (old as NSString).length
        storage.replaceCharacters(in: NSRange(location: current.length - len, length: len),
                                  with: NSAttributedString(string: new, attributes: NotesStyle.base))
        followTail?()
    }

    // MARK: Styling & saving

    nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing mask: NSTextStorageEditActions,
                                 range: NSRange, changeInLength _: Int)
    {
        guard mask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated {
            let paragraphs = (textStorage.string as NSString).paragraphRange(for: range)
            NotesStyle.apply(to: textStorage, in: paragraphs)
            scheduleSave()
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self else { return }
            self.onChange?(self.text)
        }
    }

    /// Saves right away (e.g. when the window closes or the class stops).
    func flush() {
        saveTask?.cancel()
        onChange?(text)
    }
}

/// Light Markdown styling for the editor: headings, bullets, **bold**, ★, formulas.
enum NotesStyle {
    static let size: CGFloat = 15
    static var base: [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 3
        p.paragraphSpacing = 2
        return [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.labelColor, .paragraphStyle: p]
    }

    static func apply(to storage: NSTextStorage, in range: NSRange) {
        let text = storage.string as NSString
        guard range.location != NSNotFound, NSMaxRange(range) <= text.length else { return }
        storage.beginEditing()
        storage.setAttributes(base, range: range)
        text.enumerateSubstrings(in: range, options: .byParagraphs) { line, lineRange, _, _ in
            guard let line else { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let p = NSMutableParagraphStyle()
                p.paragraphSpacingBefore = 12
                p.paragraphSpacing = 4
                storage.addAttributes([.font: NSFont.systemFont(ofSize: 20, weight: .bold), .paragraphStyle: p], range: lineRange)
                if let hashes = trimmed.range(of: #"^#+\s*"#, options: .regularExpression) {
                    let n = trimmed.distance(from: hashes.lowerBound, to: hashes.upperBound)
                    let lead = line.count - line.drop(while: { $0 == " " }).count
                    storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor,
                                         range: NSRange(location: lineRange.location + lead, length: n))
                }
                return
            }
            // Bullets: hanging indent by nesting level.
            if let m = line.range(of: #"^(\s*)[-•*]\s+"#, options: .regularExpression) {
                let marker = NSRange(m, in: line)
                let indentChars = line.prefix(while: { $0 == " " }).count
                let level = CGFloat(indentChars / 2)
                let p = NSMutableParagraphStyle()
                p.lineSpacing = 3
                p.paragraphSpacing = 2
                p.firstLineHeadIndent = 4 + level * 18
                p.headIndent = 4 + level * 18 + 14
                storage.addAttribute(.paragraphStyle, value: p, range: lineRange)
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                                     range: NSRange(location: lineRange.location + marker.location, length: marker.length))
            }
            let ns = line as NSString
            func each(_ pattern: String, _ body: (NSRange) -> Void) {
                guard let re = try? NSRegularExpression(pattern: pattern) else { return }
                for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                    body(NSRange(location: lineRange.location + m.range.location, length: m.range.length))
                }
            }
            each(#"\*\*[^*]+\*\*"#) { r in
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .semibold), range: r)
            }
            each(#"\$\$?[^$]+\$\$?"#) { r in
                storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: size - 1.5, weight: .regular),
                                       .foregroundColor: NSColor.systemIndigo], range: r)
            }
            each(#"`[^`]+`"#) { r in
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size - 1.5, weight: .regular), range: r)
            }
            each("★[^\\n]*") { r in
                storage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.18), range: r)
            }
        }
        storage.endEditing()
    }
}

/// The editor itself: a plain, fast text view on the document's storage.
struct NotesEditor: NSViewRepresentable {
    @ObservedObject var document: ClassDocument
    /// Scroll to and flash this text (a search result).
    var find: String?

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let text = scroll.documentView as! NSTextView
        text.layoutManager?.replaceTextStorage(document.storage)
        text.isRichText = false
        text.allowsUndo = true
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 28, height: 22)
        text.typingAttributes = NotesStyle.base
        scroll.drawsBackground = false
        context.coordinator.text = text
        document.followTail = { [weak text, weak scroll] in
            guard let text, let scroll else { return }
            // Follow the AI only if the student is reading the end (not scrolled up, not typing elsewhere).
            let visible = scroll.contentView.bounds
            if visible.maxY >= text.frame.height - 120 { text.scrollToEndOfDocument(nil) }
        }
        return scroll
    }

    func updateNSView(_: NSScrollView, context: Context) {
        guard let find, find != context.coordinator.lastFind, let text = context.coordinator.text else { return }
        context.coordinator.lastFind = find
        DispatchQueue.main.async {
            let hay = text.string as NSString
            var r = hay.range(of: find, options: .caseInsensitive)
            if r.location == NSNotFound, let word = find.split(separator: " ").max(by: { $0.count < $1.count }) {
                r = hay.range(of: String(word), options: .caseInsensitive)
            }
            guard r.location != NSNotFound else { return }
            text.scrollRangeToVisible(r)
            text.showFindIndicator(for: r)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var text: NSTextView?
        var lastFind: String?
    }
}
