import AVFoundation
import EvooCore
import Foundation

/// The local AI behind class notes (Qwen3 4B on every Mac — quality first).
struct ClassAI {
    var notes: (_ subject: String?, _ topic: String?, _ transcript: String, _ marks: [ClassSession.Mark.Kind]) async -> String?
    var studyPack: (_ subject: String?, _ notes: String) async -> ClassSession.StudyPack?
    var answer: (_ question: String, _ excerpts: String) async -> String?
}

/// Records a lecture: saves the audio, transcribes in pause-bounded chunks on this Mac, and writes structured
/// notes for the class's subject about once a minute — in the background, so recording never waits. The student
/// can flag moments (important / confusing / exam) and add their own notes; both steer the AI's notes.
@MainActor
final class ClassRecorder: ObservableObject {
    @Published private(set) var session: ClassSession
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    /// The last thing heard, for the live line at the bottom of the window.
    @Published private(set) var live = ""
    @Published private(set) var notesPending = 0
    @Published private(set) var level: Float = 0

    private let recorder = AudioRecorder()
    private let transcribe: ([Float]) async throws -> String
    private let ai: ClassAI?
    private var audioFile: AVAudioFile?
    private var loop: Task<Void, Never>?
    private var buffer: [Float] = []
    private var bufferStart: TimeInterval = 0
    private var pending = "" // transcript not yet turned into notes
    private var pendingStart: TimeInterval = 0
    private var startedAt = Date()
    private var busy = false
    /// Notes are written one after another in the background, in order.
    private var notesChain: Task<Void, Never>?

    init(session: ClassSession, transcribe: @escaping ([Float]) async throws -> String, ai: ClassAI?) {
        self.session = session
        self.transcribe = transcribe
        self.ai = ai
    }

    func start(microphone: String?) throws {
        recorder.onLevel = { [weak self] l in Task { @MainActor in self?.level = l } }
        try recorder.start(deviceUID: microphone)
        openAudioFile()
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
        let rest = recorder.take()
        write(rest)
        buffer += rest
        _ = recorder.stop()
        isRecording = false
        audioFile = nil // closes the file
        session.duration = elapsed
        await transcribeBuffer()
        flushNotes()
        await notesChain?.value
        ClassStore.shared.save(session)
    }

    /// A flagged moment: "Important" / "Confusing" / "On the exam".
    func mark(_ kind: ClassSession.Mark.Kind) {
        var marks = session.marks ?? []
        marks.append(.init(time: elapsed, kind: kind))
        session.marks = marks
        ClassStore.shared.save(session)
    }

    /// The student's own note, pinned to this moment.
    func addNote(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        session.notes.append(.init(time: elapsed, page: nil, text: t, mine: true))
        ClassStore.shared.save(session)
    }

    // MARK: - Audio

    /// AAC at 16 kHz mono: about 15 MB per hour.
    private func openAudioFile() {
        let url = ClassStore.shared.folder(for: session).appendingPathComponent("lecture.m4a")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: AudioRecorder.sampleRate,
                                       AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32_000]
        audioFile = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        if audioFile != nil { session.audioFile = "lecture.m4a" }
    }

    private func write(_ samples: [Float]) {
        guard let file = audioFile, !samples.isEmpty,
              let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        pcm.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in pcm.floatChannelData![0].update(from: src.baseAddress!, count: samples.count) }
        try? file.write(from: pcm)
    }

    // MARK: - Transcription & notes

    private func tick() async {
        elapsed = Date().timeIntervalSince(startedAt)
        if buffer.isEmpty { bufferStart = elapsed }
        let fresh = recorder.take()
        write(fresh)
        buffer += fresh
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
        if pending.split(separator: " ").count >= 150 { flushNotes() } // about a minute of lecture
        ClassStore.shared.save(session)
    }

    /// Queues the pending transcript to become notes (written in order, in the background).
    private func flushNotes() {
        let text = pending, time = pendingStart, end = elapsed
        guard !text.isEmpty else { return }
        pending = ""
        // Flags the student set during this stretch (and a few seconds after) steer the AI.
        let marks = (session.marks ?? []).filter { $0.time >= time - 5 && $0.time <= end + 5 }.map(\.kind)
        let previous = notesChain
        notesPending += 1
        notesChain = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let topic = ClassNotePrompt.lastTopic(in: self.session.notes.filter { $0.mine != true }.map(\.text))
            var notes: String?
            if let ai = self.ai { notes = await ai.notes(self.session.subject, topic, text, marks) }
            if notes?.isEmpty ?? true { notes = LectureNotes.bullets(from: text).joined(separator: "\n") }
            self.notesPending -= 1
            guard let notes, !notes.isEmpty else { return }
            // Keep notes in time order even if the student typed one meanwhile.
            let note = ClassSession.Note(time: time, page: nil, text: notes)
            let index = self.session.notes.firstIndex { $0.time > time } ?? self.session.notes.endIndex
            self.session.notes.insert(note, at: index)
            ClassStore.shared.save(self.session)
        }
    }
}
