import AppKit
import EvooCore
import SwiftUI
import WebKit

/// Class notes rendered like a textbook: bullets, ★ highlights, and formulas typeset with KaTeX (MIT, bundled —
/// works offline). Also exports the rendered notes to PDF.
struct NotesWebView: NSViewRepresentable {
    struct Item: Encodable, Equatable {
        let id: String
        let label: String
        let text: String
        let focused: Bool
        var mine = false
        /// Seconds into the class — clicking the note plays from here.
        var time: Double = 0
    }

    let items: [Item]
    let transcript: [String]
    /// Scroll to this note (by id) once rendered.
    let scrollTo: String?
    var exporter: NotesExporter?
    /// Click a note → play the lecture from that moment.
    var onSeek: ((TimeInterval) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "seek")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.setValue(false, forKey: "drawsBackground")
        context.coordinator.web = web
        exporter?.web = web
        if let page = NotesPage.prepare() {
            web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        exporter?.web = web
        context.coordinator.onSeek = onSeek
        context.coordinator.push(items: items, transcript: transcript, scrollTo: scrollTo)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var web: WKWebView?
        var onSeek: ((TimeInterval) -> Void)?

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            if let t = message.body as? Double { onSeek?(t) } else if let t = message.body as? Int { onSeek?(Double(t)) }
        }
        private var loaded = false
        private var pending: String?
        private var last: String?

        func push(items: [Item], transcript: [String], scrollTo: String?) {
            struct Payload: Encodable {
                let items: [Item]
                let transcript: [String]
                let scrollTo: String?
            }
            guard let data = try? JSONEncoder().encode(Payload(items: items, transcript: transcript, scrollTo: scrollTo)),
                  let json = String(data: data, encoding: .utf8), json != last else { return }
            last = json
            if loaded { web?.evaluateJavaScript("render(\(json))") } else { pending = json }
        }

        func webView(_ web: WKWebView, didFinish _: WKNavigation!) {
            loaded = true
            if let pending { web.evaluateJavaScript("render(\(pending))") }
            pending = nil
        }
    }
}

/// Lets the SwiftUI toolbar ask the web view for a PDF of the rendered notes.
@MainActor
final class NotesExporter: ObservableObject {
    weak var web: WKWebView?

    func exportPDF(named name: String) {
        guard let web else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name + ".pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Paper look for the PDF (white page, dark text), then back to the window's look.
        web.evaluateJavaScript("document.documentElement.classList.add('paper')") { _, _ in
            web.createPDF { result in
                if case let .success(data) = result { try? data.write(to: url) }
                web.evaluateJavaScript("document.documentElement.classList.remove('paper')")
            }
        }
    }
}

/// The HTML page (plus a copy of KaTeX) lives in Application Support so WebKit can read it offline.
enum NotesPage {
    static func prepare() -> URL? {
        let dir = ModelPaths.root.deletingLastPathComponent().appendingPathComponent("notes-view", isDirectory: true)
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let katex = dir.appendingPathComponent("katex")
        if !fm.fileExists(atPath: katex.appendingPathComponent("katex.min.js").path),
           let bundled = Bundle.main.url(forResource: "katex", withExtension: nil)
        {
            try? fm.removeItem(at: katex)
            try? fm.copyItem(at: bundled, to: katex)
        }
        let page = dir.appendingPathComponent("notes.html")
        try? html.write(to: page, atomically: true, encoding: .utf8)
        return page
    }

    static let html = #"""
    <!doctype html>
    <html><head><meta charset="utf-8">
    <link rel="stylesheet" href="katex/katex.min.css">
    <script src="katex/katex.min.js"></script>
    <script src="katex/auto-render.min.js"></script>
    <style>
      :root { color-scheme: light dark; --card: rgba(127,127,127,.08); --hi: rgba(255,214,10,.28); --accent: #0a84ff; }
      body { font: 14px/1.55 -apple-system, system-ui; margin: 16px; color: CanvasText; background: transparent; }
      .note { background: var(--card); border-radius: 10px; padding: 10px 14px; margin: 0 0 12px; }
      .note.focused { background: var(--hi); }
      .note { cursor: pointer; } .note:hover { outline: 1px solid rgba(10,132,255,.35); }
      .note.mine { border-left: 3px solid var(--accent); background: rgba(10,132,255,.08); }
      h3 { font-size: 15px; margin: 6px 0 6px; } strong { font-weight: 650; }
      code { font: 12.5px ui-monospace, Menlo; background: rgba(127,127,127,.15); padding: 1px 4px; border-radius: 4px; }
      .label { font-size: 11px; font-weight: 700; color: var(--accent); margin-bottom: 4px; }
      ul { margin: 0; padding-left: 18px; } li { margin: 3px 0; }
      .star { color: #d4a000; font-weight: 700; }
      .arrow { margin: 3px 0 3px 2px; }
      details { margin-top: 18px; color: GrayText; } summary { cursor: pointer; }
      .t { margin: 4px 0; font-size: 13px; }
      .empty { color: GrayText; }
      @media print { .note { break-inside: avoid; } details { display: none; } }
      html.paper { color-scheme: light; } html.paper body { background: white; color: #111; }
      html.paper .note { background: #f5f5f7; } html.paper .note.focused { background: #f5f5f7; }
      html.paper details { display: none; }
    </style></head>
    <body><div id="notes"><p class="empty">Notes appear here as the lecture goes on.</p></div>
    <details id="tx"><summary>Full transcript</summary><div id="transcript"></div></details>
    <script>
    function esc(s) { return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
    function lines(text) {
      let html = '', inList = false;
      for (let raw of text.split('\n')) {
        let line = raw.trim(); if (!line) continue;
        let bullet = /^[-•*]\s+/.test(line);
        if (bullet) { if (!inList) { html += '<ul>'; inList = true; } line = line.replace(/^[-•*]\s+/, ''); }
        else if (inList) { html += '</ul>'; inList = false; }
        if (!bullet && /^#{1,3}\s+/.test(line)) { if (inList) { html += '</ul>'; inList = false; }
          html += '<h3>' + esc(line.replace(/^#{1,3}\s+/, '')) + '</h3>'; continue; }
        let content = esc(line).replace(/★/g, '<span class="star">★</span>')
          .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>').replace(/`([^`]+)`/g, '<code>$1</code>');
        html += bullet ? '<li>' + content + '</li>' : '<div class="arrow">' + content + '</div>';
      }
      return html + (inList ? '</ul>' : '');
    }
    function render(p) {
      const notes = document.getElementById('notes');
      notes.innerHTML = p.items.length ? p.items.map(n =>
        '<div class="note' + (n.focused ? ' focused' : '') + (n.mine ? ' mine' : '') + '" id="n' + n.id +
        '" onclick="window.webkit.messageHandlers.seek.postMessage(' + n.time + ')"><div class="label">' +
        (n.mine ? '✍️ ' : '') + esc(n.label) +
        '</div>' + lines(n.text) + '</div>').join('') : '<p class="empty">Notes appear here as the lecture goes on.</p>';
      document.getElementById('transcript').innerHTML = p.transcript.map(t => '<div class="t">' + esc(t) + '</div>').join('');
      document.getElementById('tx').style.display = p.transcript.length ? '' : 'none';
      if (window.renderMathInElement) renderMathInElement(document.body, {
        delimiters: [{left: '$$', right: '$$', display: true}, {left: '$', right: '$', display: false},
                     {left: '\\(', right: '\\)', display: false}, {left: '\\[', right: '\\]', display: true}],
        throwOnError: false });
      const target = p.scrollTo ? document.getElementById('n' + p.scrollTo) : null;
      if (target) target.scrollIntoView({block: 'center'});
      else if (!p.scrollTo) window.scrollTo(0, document.body.scrollHeight);
    }
    </script></body></html>
    """#
}
