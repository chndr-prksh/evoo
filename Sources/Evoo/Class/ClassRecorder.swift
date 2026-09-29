import EvooCore
import Foundation

/// The local AI behind class notes (Qwen3 4B on every Mac — quality first).
struct ClassAI {
    /// subject, current topic, the end of the notes so far, what was said, flags, and a callback with the notes as
    /// they're written.
    var notes: (_ subject: String?, _ topic: String?, _ recent: String, _ transcript: String,
                _ marks: [ClassSession.Mark.Kind], _ onText: (@Sendable (String) -> Void)?) async -> String?
    var studyPack: (_ subject: String?, _ notes: String) async -> ClassSession.StudyPack?
    var answer: (_ question: String, _ excerpts: String) async -> String?
}

/// Listens to a lecture, transcribes it in pause-bounded chunks on this Mac, and about once a minute has the local
/// AI jot down what mattered — typed into the notes document word by word, while the student can edit it. No audio
/// is kept.
@MainActor
final class ClassRecorder: ObservableObject {
    @Published private(set) var session: ClassSession
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    /// The last thing heard, for the live line at the bottom of the window.
    @Published private(set) var live = ""
    @Published private(set) var writing = false
    @Published private(set) var level: Float = 0
    let document: ClassDocument

    private let recorder = AudioRecorder()
    private let transcribe: ([Float]) async throws -> String
    private let ai: ClassAI?
    private var loop: Task<Void, Never>?
    private var buffer: [Float] = []
    private var bufferStart: TimeInterval = 0
    private var pending = "" // transcript not yet turned into notes
    private var pendingStart: TimeInterval = 0
    private var startedAt = Date()
    private var busy = false
    /// Notes are written one stretch after another, in order.
    private var notesChain: Task<Void, Never>?
    private var queued = 0

    init(session: ClassSession, transcribe: @escaping ([Float]) async throws -> String, ai: ClassAI?) {
        self.session = session
        self.transcribe = transcribe
        self.ai = ai
        document = ClassDocument(text: session.notesText)
        document.onChange = { [weak self] text in
            guard let self else { return }
            self.session.document = text
            ClassStore.shared.save(self.session)
        }
    }

    func start(microphone: String?) throws {
        recorder.onLevel = { [weak self] l in Task { @MainActor in self?.level = l } }
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
        session.duration = elapsed
        await transcribeBuffer()
        flushNotes()
        await notesChain?.value
        document.flush()
        save()
    }

    /// A flagged moment: "Important" / "Confusing" / "On the exam" — steers the next notes.
    func mark(_ kind: ClassSession.Mark.Kind) {
        var marks = session.marks ?? []
        marks.append(.init(time: elapsed, kind: kind))
        session.marks = marks
        save()
    }

    private func save() {
        session.document = document.text
        ClassStore.shared.save(session)
    }

    // MARK: - Transcription & notes

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
        session.segments.append(.init(time: time, page: nil, text: text))
        live = text
        if pending.isEmpty { pendingStart = time }
        pending += (pending.isEmpty ? "" : " ") + text
        if pending.split(separator: " ").count >= 140 { flushNotes() } // about a minute of lecture
        save()
    }

    /// Queues the pending transcript to become notes (written in order, in the background).
    private func flushNotes() {
        let text = pending, time = pendingStart, end = elapsed
        guard !text.isEmpty else { return }
        pending = ""
        // Flags the student set during this stretch (and a few seconds after) steer the AI.
        let marks = (session.marks ?? []).filter { $0.time >= time - 5 && $0.time <= end + 5 }.map(\.kind)
        let previous = notesChain
        queued += 1
        writing = true
        notesChain = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            defer {
                self.queued -= 1
                self.writing = self.queued > 0
            }
            // The notes as the student has them now (they may have edited), so the AI continues from there.
            let current = self.document.text
            let topic = ClassNotePrompt.lastTopic(in: [current])
            let recent = String(current.suffix(600))
            let doc = self.document
            let id = doc.begin()
            var notes: String?
            if let ai = self.ai {
                let raw = await ai.notes(self.session.subject, topic, recent, text, marks) { partial in
                    DispatchQueue.main.async { MainActor.assumeIsolated { doc.stream(partial, chunk: id) } }
                }
                if let raw {
                    notes = ClassNotePrompt.tidy(raw, lastTopic: topic, existing: current, heard: text,
                                                 flagged: marks.contains { $0 != .confusing })
                }
            } else {
                notes = LectureNotes.bullets(from: text).map { "- " + $0 }.joined(separator: "\n")
            }
            doc.finish(notes ?? "", chunk: id)
            if let notes, !notes.isEmpty {
                // Timed copy for search ("search note …" finds when it was said).
                let index = self.session.notes.firstIndex { $0.time > time } ?? self.session.notes.endIndex
                self.session.notes.insert(.init(time: time, page: nil, text: notes), at: index)
            }
            self.save()
        }
    }
}
