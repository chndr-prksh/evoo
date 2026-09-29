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
        /// Seconds into the class — clicking the note plays from here (negative: not clickable).
        var time: Double = 0
        /// Shown folded, opened with a click (study pack sections).
        var collapsed = false
        /// A section of the study sheet rather than a timed note.
        var section = false
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
      :root { color-scheme: light dark; --hi: rgba(255,214,10,.22); --accent: #0a84ff; --muted: GrayText;
              --rule: rgba(127,127,127,.18); }
      body { font: 15px/1.6 -apple-system, system-ui; margin: 0; padding: 22px 28px 40px; color: CanvasText;
             background: transparent; max-width: 780px; }
      .note { position: relative; padding: 2px 0 2px 64px; margin: 0 0 6px; border-radius: 6px; cursor: pointer; }
      .note:hover { background: rgba(127,127,127,.06); }
      .note:hover .label { color: var(--accent); }
      .note.focused { background: var(--hi); }
      .note.mine { border-left: 3px solid var(--accent); padding-left: 61px; }
      .label { position: absolute; left: 6px; top: 5px; font: 11px ui-monospace, Menlo; color: var(--muted); }
      h3 { font-size: 18px; font-weight: 700; margin: 22px 0 6px; padding-bottom: 4px; border-bottom: 1px solid var(--rule); }
      .note:first-child h3 { margin-top: 4px; }
      strong { font-weight: 650; } em { font-style: italic; }
      code { font: 13px ui-monospace, Menlo; background: rgba(127,127,127,.15); padding: 1px 4px; border-radius: 4px; }
      ul { margin: 0; padding-left: 18px; } li { margin: 2px 0; } ul ul { margin-top: 2px; }
      .star { color: #d4a000; font-weight: 700; }
      .arrow { margin: 3px 0; }
      .katex-display { margin: 6px 0; text-align: left; } .katex-display > .katex { text-align: left; }
      .sec { margin: 0 0 18px; padding: 14px 18px; border: 1px solid var(--rule); border-radius: 12px; }
      .sec > summary, .sec > .head { font-size: 13px; font-weight: 700; text-transform: uppercase; letter-spacing: .04em;
              color: var(--muted); cursor: pointer; list-style: none; margin-bottom: 6px; }
      .sec > summary::before { content: "▸ "; } .sec[open] > summary::before { content: "▾ "; }
      .sec.clickable { cursor: pointer; }
      .doc h3:first-child { margin-top: 0; }
      details.tx { margin-top: 18px; color: var(--muted); } details.tx summary { cursor: pointer; }
      .t { margin: 4px 0; font-size: 13px; }
      .empty { color: var(--muted); }
      @media print { .note { break-inside: avoid; } details.tx { display: none; } }
      html.paper { color-scheme: light; } html.paper body { background: white; color: #111; }
      html.paper .note.focused { background: none; } html.paper details.tx { display: none; }
    </style></head>
    <body><div id="notes"><p class="empty">Notes appear here as the lecture goes on.</p></div>
    <details id="tx" class="tx"><summary>Full transcript</summary><div id="transcript"></div></details>
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
          .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>').replace(/(^|[^*])\*([^*\s][^*]*?)\*(?!\*)/g, '$1<em>$2</em>').replace(/`([^`]+)`/g, '<code>$1</code>');
        html += bullet ? '<li>' + content + '</li>' : '<div class="arrow">' + content + '</div>';
      }
      return html + (inList ? '</ul>' : '');
    }
    function render(p) {
      const notes = document.getElementById('notes');
      const seek = n => n.time >= 0 ? ' onclick="window.webkit.messageHandlers.seek.postMessage(' + n.time + ')"' : '';
      notes.innerHTML = p.items.length ? p.items.map(n => {
        if (n.section) {
          const body = lines(n.text);
          if (!n.label) return '<div class="doc">' + body + '</div>';
          return n.collapsed
            ? '<details class="sec" id="n' + n.id + '"><summary>' + esc(n.label) + '</summary>' + body + '</details>'
            : '<div class="sec' + (n.time >= 0 ? ' clickable' : '') + '" id="n' + n.id + '"' + seek(n) + '><div class="head">' +
              esc(n.label) + '</div>' + body + '</div>';
        }
        return '<div class="note' + (n.focused ? ' focused' : '') + (n.mine ? ' mine' : '') + '" id="n' + n.id + '"' + seek(n) +
          '><div class="label">' + (n.mine ? '✍️ ' : '') + esc(n.label) + '</div>' + lines(n.text) + '</div>';
      }).join('') : '<p class="empty">Notes appear here as the lecture goes on.</p>';
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
