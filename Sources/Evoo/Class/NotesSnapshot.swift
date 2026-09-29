#if DEBUG
import AppKit
import WebKit

/// `Evoo.app --args --snapshot-notes out.pdf` renders sample class notes (with formulas) to a PDF and quits.
@MainActor
final class NotesSnapshot: NSObject, WKNavigationDelegate {
    static var current: NotesSnapshot?
    private let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 700, height: 900))
    private let out: URL

    init(out: URL) {
        self.out = out
        super.init()
        web.navigationDelegate = self
        if let page = NotesPage.prepare() { web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent()) }
    }

    func webView(_ web: WKWebView, didFinish _: WKNavigation!) {
        let sample = #"""
        {"items":[{"id":"1","label":"00:12 · Slide 2","focused":false,"text":"- $P(A \\mid B) = \\frac{P(A \\cap B)}{P(B)}$\n- Example: rolling a fair die → even outcomes: 2, 4, 6 → $P(\\text{6} \\mid \\text{even}) = \\frac{1}{3}$\n- ★ Independence is on the exam\n→ If $A$ and $B$ are independent, $P(A \\mid B) = P(A)$"},{"id":"2","label":"01:40 · Slide 3","focused":true,"text":"- Variance: $$\\operatorname{Var}(X) = E[X^2] - (E[X])^2$$\n- ★ For independent $X, Y$: $\\operatorname{Var}(X+Y)=\\operatorname{Var}(X)+\\operatorname{Var}(Y)$"}],"transcript":["[00:12] Okay so today conditional probability…"],"scrollTo":null}
        """#
        web.evaluateJavaScript("render(\(sample)); document.documentElement.classList.add('paper')") { _, _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                web.createPDF { result in
                    if case let .success(data) = result { try? data.write(to: self.out) }
                    exit(0)
                }
            }
        }
    }
}
#endif

#if DEBUG
import SwiftUI

/// `Evoo --snapshot-editor out.png`: the notes editor with the AI typing into it, rendered off-screen.
@MainActor
enum EditorSnapshot {
    static func run(out: URL) {
        let doc = ClassDocument(text: "## Conditional probability\n- **P(A|B)** — prob. of A, given B\n- $$P(A\\mid B)=\\frac{P(A\\cap B)}{P(B)}$$ ★ midterm\n")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 420), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: NotesEditor(document: doc).frame(width: 720, height: 420).background(Color.white))
        Task { @MainActor in
            // Simulate the AI streaming a new stretch word by word, with a repeated heading the tidy pass removes.
            let final = "## Bayes' theorem\n- flips conditional: $P(A|B)$ from $P(B|A)$\n  - ex: disease test → 16.7%"
            let id = doc.begin()
            var partial = ""
            for word in final.split(separator: " ", omittingEmptySubsequences: false) {
                partial += (partial.isEmpty ? "" : " ") + word
                doc.stream(partial, chunk: id)
                try? await Task.sleep(for: .milliseconds(10))
            }
            doc.finish(final, chunk: id)
            try? await Task.sleep(for: .milliseconds(300))
            let view = window.contentView!
            view.layoutSubtreeIfNeeded()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: out)
            }
            print(doc.text)
            exit(0)
        }
    }
}
#endif
