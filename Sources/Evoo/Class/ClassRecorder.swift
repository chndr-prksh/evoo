import EvooCore
import Foundation
import PDFKit

/// Records a lecture: listens continuously, transcribes in pause-bounded chunks on this Mac, follows the
/// slides of the class PDF (if any), and writes notes every minute or so and whenever the slide changes.
@MainActor
final class ClassRecorder: ObservableObject {
    @Published private(set) var session: ClassSession
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var currentPage = 0
    /// The last thing heard, for the live line at the bottom of the window.
    @Published private(set) var live = ""

    private let recorder = AudioRecorder()
    private let transcribe: ([Float]) async throws -> String
    /// Local LLM note writer (16 GB Macs with Smart cleanup); nil = the built-in bullet writer.
    private let writeNotes: ((String?, String) async -> String?)?
    private let pageTexts: [String]
    private var tracker: SlideTracker
    private var loop: Task<Void, Never>?
    private var buffer: [Float] = []
    private var bufferStart: TimeInterval = 0
    private var pending = "" // transcript not yet turned into notes
    private var pendingPage: Int?
    private var pendingStart: TimeInterval = 0
    private var startedAt = Date()
    private var busy = false
    /// Notes are written one after another in the background, so recording never waits for the AI.
    private var notesChain: Task<Void, Never>?
    @Published private(set) var notesPending = 0

    init(session: ClassSession, pdf: PDFDocument?, transcribe: @escaping ([Float]) async throws -> String,
         writeNotes: ((String?, String) async -> String?)?)
    {
        self.session = session
        self.transcribe = transcribe
        self.writeNotes = writeNotes
        pageTexts = pdf.map { doc in (0 ..< doc.pageCount).map { doc.page(at: $0)?.string ?? "" } } ?? []
        tracker = SlideTracker(pages: pageTexts)
    }

    var hasSlides: Bool { !pageTexts.isEmpty }

    func start(microphone: String?) throws {
        try recorder.start(deviceUID: microphone)
        isRecording = true
        startedAt = Date().addingTimeInterval(-elapsed)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self?.tick()
            }
        }
    }

    func stop() async {
        loop?.cancel()
        buffer += recorder.take()
        _ = recorder.stop()
        isRecording = false
        await transcribeBuffer()
        flushNotes()
        await notesChain?.value
        ClassStore.shared.save(session)
    }

    /// Manual slide change (← / → or clicking a page).
    func setPage(_ page: Int) {
        guard hasSlides else { return }
        if page != tracker.current { flushNotes() }
        tracker.set(page)
        currentPage = tracker.current
    }

    private func tick() async {
        elapsed = Date().timeIntervalSince(startedAt)
        if buffer.isEmpty { bufferStart = elapsed }
        buffer += recorder.take()
        let seconds = Double(buffer.count) / AudioRecorder.sampleRate
        // Cut at a natural pause after 8 s, or at 25 s regardless.
        let cut = (seconds >= 8 && AudioStats.endsInPause(buffer, seconds: 0.4)) || seconds >= 25
        guard cut, !busy else { return }
        await transcribeBuffer()
    }

    private func transcribeBuffer() async {
        guard !buffer.isEmpty else { return }
        busy = true
        defer { busy = false }
        let chunk = buffer, time = bufferStart
        buffer = []
        guard let speech = AudioStats.speechRange(chunk),
              let text = try? await transcribe(Array(chunk[speech])).trimmingCharacters(in: .whitespaces),
              !text.isEmpty else { return }
        let before = tracker.current
        if hasSlides {
            let recent = (session.segments.suffix(3).map(\.text) + [text]).joined(separator: " ")
            tracker.update(with: recent)
            currentPage = tracker.current
        }
        session.segments.append(.init(time: time, page: hasSlides ? tracker.current : nil, text: text))
        live = text
        // A slide change closes the notes for the previous slide.
        if hasSlides, tracker.current != before { flushNotes() }
        if pending.isEmpty {
            pendingStart = time
            pendingPage = hasSlides ? tracker.current : nil
        }
        pending += (pending.isEmpty ? "" : " ") + text
        if pending.split(separator: " ").count >= 120 { flushNotes() } // about a minute of lecture
        ClassStore.shared.save(session)
    }

    /// Queues the pending transcript to become notes for its slide (written in order, in the background).
    private func flushNotes() {
        let text = pending, page = pendingPage, time = pendingStart
        guard !text.isEmpty else { return }
        pending = ""
        let slide = page.flatMap { $0 < pageTexts.count ? pageTexts[$0] : nil }
        let previous = notesChain
        notesPending += 1
        notesChain = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            var notes: String?
            if let writeNotes = self.writeNotes { notes = await writeNotes(slide, text) }
            if notes?.isEmpty ?? true { notes = LectureNotes.bullets(from: text).joined(separator: "\n") }
            self.notesPending -= 1
            guard let notes, !notes.isEmpty else { return }
            self.session.notes.append(.init(time: time, page: page, text: notes))
            ClassStore.shared.save(self.session)
        }
    }
}
