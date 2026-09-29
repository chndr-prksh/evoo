import EvooCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Window state: which class is open, the live recorder, and search.
@MainActor
final class ClassNotesModel: ObservableObject {
    static let shared = ClassNotesModel()

    @Published var selectedID: UUID?
    @Published var recorder: ClassRecorder?
    @Published var query = ""
    /// A search result to scroll to and highlight (seconds into that class).
    @Published var focusTime: TimeInterval?
    @Published var draftTitle = ""
    @Published var draftPDF: URL?
    /// Supplied by the dictation controller: builds a recorder with the speech engine and note writer.
    var makeRecorder: ((ClassSession, PDFDocument?) -> ClassRecorder?)?
    var microphone: () -> String? = { nil }

    func startClass() {
        var session = ClassSession(title: draftTitle.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Class · " + Date().formatted(date: .abbreviated, time: .shortened) : draftTitle)
        if let pdf = draftPDF { ClassStore.shared.attachPDF(pdf, to: &session) }
        ClassStore.shared.save(session)
        let doc = ClassStore.shared.pdfURL(for: session).flatMap(PDFDocument.init(url:))
        guard let rec = makeRecorder?(session, doc) else { return }
        do {
            try rec.start(microphone: microphone())
            recorder = rec
            selectedID = session.id
            draftTitle = ""
            draftPDF = nil
        } catch {
            ClassStore.shared.delete(session)
        }
    }

    func stopClass() {
        guard let rec = recorder else { return }
        Task {
            await rec.stop()
            recorder = nil
        }
    }

    func newClass() {
        selectedID = nil
        focusTime = nil
    }
}

struct ClassNotesView: View {
    @ObservedObject var model: ClassNotesModel
    @ObservedObject var store: ClassStore
    @ObservedObject var controller: DictationController

    private var hits: [ClassSearch.Hit] {
        model.query.trimmingCharacters(in: .whitespaces).isEmpty ? [] : ClassSearch.search(model.query, in: store.sessions)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 250)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 980, minHeight: 620)
    }

    // MARK: Sidebar: search + past classes

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.newClass()
            } label: {
                Label("New class", systemImage: "plus.circle.fill").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .disabled(model.recorder != nil)
            TextField("Search notes", text: $model.query)
                .textFieldStyle(.roundedBorder)
            if !hits.isEmpty {
                Text("\(hits.count) matches").font(.caption).foregroundStyle(.secondary)
                List(hits) { hit in
                    let session = store.sessions.first { $0.id == hit.sessionID }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session?.title ?? "Class").font(.caption.bold())
                        Text(when(session, hit.time) + (hit.page.map { " · slide \($0 + 1)" } ?? ""))
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(hit.snippet).font(.caption).lineLimit(3)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { open(hit) }
                }
                .listStyle(.plain)
            } else {
                Text("Classes").font(.caption.bold()).foregroundStyle(.secondary)
                List(store.sessions) { session in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title).lineLimit(1)
                        Text(session.started.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.selectedID = session.id
                        model.focusTime = nil
                    }
                    .listRowBackground(model.selectedID == session.id ? Color.accentColor.opacity(0.15) : Color.clear)
                }
                .listStyle(.plain)
            }
        }
        .padding(12)
    }

    private func open(_ hit: ClassSearch.Hit) {
        model.selectedID = hit.sessionID
        model.focusTime = hit.time
    }

    private func when(_ session: ClassSession?, _ time: TimeInterval) -> String {
        guard let session else { return "" }
        return session.started.addingTimeInterval(time).formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let rec = model.recorder, rec.session.id == model.selectedID {
            LiveClassView(recorder: rec, stop: model.stopClass)
        } else if let id = model.selectedID, let session = store.sessions.first(where: { $0.id == id }) {
            ClassPageView(session: session, pdf: store.pdfURL(for: session).flatMap(PDFDocument.init(url:)),
                          page: focusPage(session), focusTime: model.focusTime)
        } else {
            startPanel
        }
    }

    private func focusPage(_ session: ClassSession) -> Int {
        guard let t = model.focusTime else { return 0 }
        return session.segments.last { $0.time <= t }?.page ?? session.notes.last { $0.time <= t }?.page ?? 0
    }

    private var startPanel: some View {
        VStack(spacing: 22) {
            Image(systemName: "graduationcap.fill").font(.system(size: 44)).foregroundStyle(.tint)
            Text("Take notes in class").font(.system(size: 26, weight: .bold))
            Text("Evoo listens to the lecture and writes notes as it goes — on this Mac, nothing uploaded.")
                .foregroundStyle(.secondary)
            TextField("Class name (e.g. Probability — Lecture 4)", text: $model.draftTitle)
                .textFieldStyle(.roundedBorder)
                .frame(width: 420)
            dropZone
            Button {
                model.startClass()
            } label: {
                Label("Start class", systemImage: "record.circle").padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("No PDF? That's fine — Evoo takes notes from the lecture alone.")
                .font(.caption).foregroundStyle(.secondary)
            notesModelStatus
        }
        .padding(40)
    }

    /// Notes are written by the best local model on every Mac; it's downloaded once.
    @ViewBuilder private var notesModelStatus: some View {
        if let p = controller.refinerDownloadProgress {
            ProgressView(value: p) { Text("Downloading the notes model… \(Int(p * 100))%").font(.caption) }
                .frame(width: 320)
        } else if !controller.notesModelInstalled {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(.yellow)
                Text("For high-quality notes (formulas, worked examples), download the notes model — 2.5 GB, once.")
                    .font(.caption)
                Button("Download") { controller.downloadNotesModel() }
            }
            .frame(width: 520)
        } else if SystemInfo.isLowMemory {
            Text("Notes are written by a local AI and may appear a little behind the lecture on this Mac — nothing is lost.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: model.draftPDF == nil ? "doc.badge.plus" : "doc.fill")
                .font(.system(size: 28)).foregroundStyle(.tint)
            Text(model.draftPDF?.lastPathComponent ?? "Drop the class PDF here (optional)")
                .font(.headline)
            Text(model.draftPDF == nil ? "Slides or notes from the professor — Evoo follows along and writes beside each slide."
                : "Evoo will follow these slides during the lecture.")
                .font(.caption).foregroundStyle(.secondary)
            Button(model.draftPDF == nil ? "Choose PDF…" : "Choose another…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.pdf]
                if panel.runModal() == .OK { model.draftPDF = panel.url }
            }
        }
        .frame(width: 420, height: 150)
        .background(RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .foregroundStyle(.secondary.opacity(0.5)))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension.lowercased() == "pdf" else { return }
                Task { @MainActor in model.draftPDF = url }
            }
            return true
        }
    }
}

/// A class in progress: slides on the left (if any), notes appearing on the right, live transcript below.
private struct LiveClassView: View {
    @ObservedObject var recorder: ClassRecorder
    let stop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle().fill(.red).frame(width: 9, height: 9)
                Text(recorder.session.title).font(.headline)
                Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern: .hourMinuteSecond)))
                    .monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button("Stop class", action: stop).buttonStyle(.borderedProminent).tint(.red)
            }
            .padding(12)
            Divider()
            ClassPageView(session: recorder.session,
                          pdf: ClassStore.shared.pdfURL(for: recorder.session).flatMap(PDFDocument.init(url:)),
                          page: recorder.currentPage, focusTime: nil,
                          onPageChange: recorder.hasSlides ? { recorder.setPage($0) } : nil)
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "waveform").foregroundStyle(.secondary)
                Text(recorder.live.isEmpty ? "Listening…" : recorder.live)
                    .lineLimit(1).foregroundStyle(.secondary)
                Spacer()
                if recorder.notesPending > 0 {
                    ProgressView().controlSize(.small)
                    Text("Writing notes…").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .padding(10)
        }
    }
}

/// Slides + notes side by side (review or live).
private struct ClassPageView: View {
    let session: ClassSession
    let pdf: PDFDocument?
    let page: Int
    let focusTime: TimeInterval?
    var onPageChange: ((Int) -> Void)?

    var body: some View {
        HSplitView {
            if let pdf {
                PDFPageView(document: pdf, page: page, onPageChange: onPageChange)
                    .frame(minWidth: 380)
            }
            notes.frame(minWidth: 360)
        }
    }

    private var notes: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(session.started.formatted(date: .complete, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Export Markdown…", action: export).font(.caption)
                    }
                    if session.notes.isEmpty && session.segments.isEmpty {
                        Text("Notes appear here as the lecture goes on.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(session.notes.enumerated()), id: \.offset) { _, note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(label(note.time, note.page)).font(.caption.bold()).foregroundStyle(.tint)
                            Text(note.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(isFocused(note.time)
                                ? Color.yellow.opacity(0.25) : Color.secondary.opacity(0.07)))
                        .id(note.time)
                    }
                    if !session.segments.isEmpty {
                        DisclosureGroup("Full transcript") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(session.segments.enumerated()), id: \.offset) { _, s in
                                    Text("[\(clock(s.time))] ").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                        + Text(s.text).font(.callout)
                                }
                            }
                            .textSelection(.enabled)
                        }
                    }
                }
                .padding(16)
            }
            .onAppear { scroll(proxy) }
            .onChange(of: focusTime) { _, _ in scroll(proxy) }
            .onChange(of: session.notes.count) { _, _ in
                if focusTime == nil, let last = session.notes.last { withAnimation { proxy.scrollTo(last.time, anchor: .bottom) } }
            }
        }
    }

    private func isFocused(_ t: TimeInterval) -> Bool {
        guard let f = focusTime else { return false }
        let next = session.notes.first { $0.time > t }?.time ?? .infinity
        return f >= t && f < next
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let f = focusTime, let note = session.notes.last(where: { $0.time <= f }) ?? session.notes.first else { return }
        withAnimation { proxy.scrollTo(note.time, anchor: .center) }
    }

    private func label(_ t: TimeInterval, _ page: Int?) -> String {
        clock(t) + (page.map { " · Slide \($0 + 1)" } ?? "")
    }

    private func clock(_ t: TimeInterval) -> String {
        Duration.seconds(t).formatted(.time(pattern: .minuteSecond))
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = session.title + ".md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? session.markdown().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

/// PDFKit page view that follows the current slide and reports manual page turns.
private struct PDFPageView: NSViewRepresentable {
    let document: PDFDocument
    let page: Int
    var onPageChange: ((Int) -> Void)?

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePage
        view.displaysPageBreaks = false
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.changed(_:)),
                                               name: .PDFViewPageChanged, object: view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.onPageChange = onPageChange
        if view.document !== document { view.document = document }
        if let target = document.page(at: page), view.currentPage != target {
            context.coordinator.programmatic = true
            view.go(to: target)
            context.coordinator.programmatic = false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var onPageChange: ((Int) -> Void)?
        var programmatic = false

        @objc func changed(_ note: Notification) {
            guard !programmatic, let view = note.object as? PDFView, let page = view.currentPage,
                  let index = view.document?.index(for: page) else { return }
            onPageChange?(index)
        }
    }
}
