import EvooCore
import SwiftUI
import UniformTypeIdentifiers

/// Window state: which class is open, the live recorder, search, playback and the local AI.
@MainActor
final class ClassNotesModel: ObservableObject {
    static let shared = ClassNotesModel()

    @Published var selectedID: UUID?
    @Published var recorder: ClassRecorder?
    @Published var query = ""
    /// A search result to scroll to and highlight (seconds into that class).
    @Published var focusTime: TimeInterval?
    @Published var draftTitle = ""
    @Published var draftSubject = UserDefaults.standard.string(forKey: "lastClassSubject") ?? ""
    @Published var makingStudyPack: UUID?
    let player = LecturePlayer()
    /// Supplied by the dictation controller.
    var makeRecorder: ((ClassSession) -> ClassRecorder?)?
    var ai: () -> ClassAI? = { nil }
    var microphone: () -> String? = { nil }

    func startClass() {
        let subject = draftSubject.trimmingCharacters(in: .whitespaces)
        let title = draftTitle.trimmingCharacters(in: .whitespaces)
        let session = ClassSession(title: title.isEmpty
            ? (subject.isEmpty ? "Class" : subject) + " · " + Date().formatted(date: .abbreviated, time: .shortened) : title,
            subject: subject.isEmpty ? nil : subject)
        UserDefaults.standard.set(subject, forKey: "lastClassSubject")
        ClassStore.shared.save(session)
        guard let rec = makeRecorder?(session) else { return }
        do {
            try rec.start(microphone: microphone())
            player.stop()
            recorder = rec
            selectedID = session.id
            draftTitle = ""
        } catch {
            ClassStore.shared.delete(session)
        }
    }

    func stopClass() {
        guard let rec = recorder else { return }
        Task {
            await rec.stop()
            recorder = nil
            makeStudyPack(for: rec.session) // straight into review mode with a study pack on the way
        }
    }

    func newClass() {
        selectedID = nil
        focusTime = nil
        player.stop()
    }

    /// Summary, key terms, questions, flashcards and to-dos, made by the local AI from the notes.
    func makeStudyPack(for session: ClassSession) {
        guard let ai = ai(), makingStudyPack == nil, !session.notes.isEmpty else { return }
        makingStudyPack = session.id
        let notes = session.notes.map { $0.mine == true ? "My note: " + $0.text : $0.text }.joined(separator: "\n")
        Task {
            if let pack = await ai.studyPack(session.subject, notes),
               var latest = ClassStore.shared.sessions.first(where: { $0.id == session.id })
            {
                latest.studyPack = pack
                ClassStore.shared.save(latest)
            }
            makingStudyPack = nil
        }
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
            sidebar.frame(width: 260)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 640)
    }

    // MARK: Sidebar — search, and classes grouped by subject

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.newClass()
            } label: {
                Label("New class", systemImage: "plus.circle.fill").font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .disabled(model.recorder != nil)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search all notes", text: $model.query).textFieldStyle(.plain)
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))

            if !model.query.isEmpty {
                Text(hits.isEmpty ? "No matches" : "\(hits.count) matches").font(.caption).foregroundStyle(.secondary)
                List(hits) { hit in
                    let session = store.sessions.first { $0.id == hit.sessionID }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session?.title ?? "Class").font(.caption.bold()).lineLimit(1)
                        Text(when(session, hit.time)).font(.caption2).foregroundStyle(.secondary)
                        Text(hit.snippet).font(.caption).lineLimit(3)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.selectedID = hit.sessionID
                        model.focusTime = hit.time
                    }
                }
                .listStyle(.plain)
            } else {
                let groups = Dictionary(grouping: store.sessions) { $0.subject ?? "Other" }
                List {
                    ForEach(groups.keys.sorted(), id: \.self) { subject in
                        Section(subject) {
                            ForEach(groups[subject]!) { session in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title).lineLimit(1)
                                    Text(session.started.formatted(date: .abbreviated, time: .shortened)
                                        + (session.duration.map { " · " + minutes($0) } ?? ""))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    model.selectedID = session.id
                                    model.focusTime = nil
                                }
                                .listRowBackground(model.selectedID == session.id ? Color.accentColor.opacity(0.15) : Color.clear)
                                .contextMenu {
                                    Button("Delete class", role: .destructive) { store.delete(session) }
                                        .disabled(model.recorder?.session.id == session.id)
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                if store.sessions.isEmpty {
                    Text("Your classes will appear here, grouped by subject.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Label("Recorded and processed on this Mac", systemImage: "lock.fill")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
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
            ReviewClassView(session: session, model: model, player: model.player)
                .id(session.id)
        } else {
            startPanel
        }
    }

    private var startPanel: some View {
        VStack(spacing: 20) {
            Image(systemName: "graduationcap.fill").font(.system(size: 44)).foregroundStyle(.tint)
            Text("Take notes in class").font(.system(size: 26, weight: .bold))
            Text("Evoo listens to the lecture and writes structured notes as it goes — on this Mac, nothing uploaded.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("What's the subject?").font(.headline)
                HStack {
                    TextField("e.g. Probability, Constitutional Law, Organic Chemistry", text: $model.draftSubject)
                        .textFieldStyle(.roundedBorder)
                    Menu("Pick") {
                        ForEach(ClassNotePrompt.commonSubjects, id: \.self) { subject in
                            Button(subject) { model.draftSubject = subject }
                        }
                    }
                    .fixedSize()
                }
                Text("Notes are written the way that subject is taught — formulas for math, dates and causes for history, cases for law, code for programming.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Lecture name (optional)", text: $model.draftTitle)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 6)
            }
            .frame(width: 480)
            Button {
                model.startClass()
            } label: {
                Label("Start class", systemImage: "record.circle").padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            HStack(spacing: 18) {
                Label("Flag moments", systemImage: "star")
                Label("Replay any note", systemImage: "play.circle")
                Label("Flashcards", systemImage: "rectangle.on.rectangle")
                Label("Ask your lecture", systemImage: "questionmark.bubble")
            }
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
                Text("For high-quality notes, study packs and Q&A, download the notes model — 2.5 GB, once.")
                    .font(.caption)
                Button("Download") { controller.downloadNotesModel() }
            }
            .frame(width: 540)
        } else if SystemInfo.isLowMemory {
            Text("Notes are written by a local AI and may appear a little behind the lecture on this Mac — nothing is lost.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Live class

private struct LiveClassView: View {
    @ObservedObject var recorder: ClassRecorder
    let stop: () -> Void
    @State private var myNote = ""
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle().fill(.red).frame(width: 10, height: 10)
                    .opacity(recorder.isRecording ? 1 : 0.3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(recorder.session.title).font(.headline).lineLimit(1)
                    if let subject = recorder.session.subject {
                        Text(subject).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern: .hourMinuteSecond)))
                    .font(.system(.title3, design: .rounded).monospacedDigit())
                LevelMeter(level: recorder.level).frame(width: 60, height: 14)
                Spacer()
                ForEach(ClassSession.Mark.Kind.allCases, id: \.self) { kind in
                    Button {
                        recorder.mark(kind)
                    } label: {
                        Text("\(kind.symbol) \(kind.label)")
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(ClassSession.Mark.Kind.allCases.firstIndex(of: kind)! + 1))),
                                      modifiers: .command)
                    .help("Flag this moment (⌘\(ClassSession.Mark.Kind.allCases.firstIndex(of: kind)! + 1))")
                }
                Button("Stop class", action: stop).buttonStyle(.borderedProminent).tint(.red)
            }
            .padding(12)
            Divider()
            NotesWebView(items: noteItems(recorder.session, focusTime: nil), transcript: [], scrollTo: nil)
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil").foregroundStyle(.tint)
                TextField("Add your own note — pinned to this moment (⏎)", text: $myNote)
                    .textFieldStyle(.plain)
                    .focused($noteFocused)
                    .onSubmit {
                        recorder.addNote(myNote)
                        myNote = ""
                    }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06))
            HStack(spacing: 8) {
                Image(systemName: "waveform").foregroundStyle(.secondary)
                Text(recorder.live.isEmpty ? "Listening…" : recorder.live).lineLimit(1).foregroundStyle(.secondary)
                Spacer()
                if recorder.notesPending > 0 {
                    ProgressView().controlSize(.small)
                    Text("Writing notes…").foregroundStyle(.secondary)
                }
                if let marks = recorder.session.marks, !marks.isEmpty {
                    Text(marks.map(\.kind.symbol).suffix(8).joined()).help("Moments you flagged")
                }
            }
            .font(.callout)
            .padding(10)
        }
    }
}

private struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(Color.green).frame(width: g.size.width * CGFloat(min(1, max(0.04, level))))
            }
        }
        .animation(.linear(duration: 0.1), value: level)
    }
}

// MARK: - Review

private struct ReviewClassView: View {
    let session: ClassSession
    @ObservedObject var model: ClassNotesModel
    @ObservedObject var player: LecturePlayer
    @StateObject private var exporter = NotesExporter()
    @State private var tab = Tab.notes

    enum Tab: String, CaseIterable {
        case notes = "Notes", transcript = "Transcript", study = "Study", flashcards = "Flashcards", ask = "Ask"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch tab {
                case .notes:
                    NotesWebView(items: noteItems(session, focusTime: model.focusTime), transcript: [],
                                 scrollTo: focusedNoteID, exporter: exporter, onSeek: seek)
                case .transcript: TranscriptView(session: session, player: player, seek: seek)
                case .study: StudyView(session: session, model: model)
                case .flashcards: FlashcardsView(cards: session.studyPack?.flashcards ?? [], makePack: {
                        model.makeStudyPack(for: session)
                    }, making: model.makingStudyPack == session.id)
                case .ask: AskView(session: session, ai: model.ai(), seek: seek)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if player.isAvailable {
                Divider()
                PlayerBar(player: player, marks: session.marks ?? [])
            }
        }
        .onAppear {
            player.load(session.audioFile.map { ClassStore.shared.folder(for: session).appendingPathComponent($0) })
            if model.focusTime != nil { tab = .notes }
        }
        .onChange(of: model.focusTime) { _, t in if t != nil { tab = .notes } }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(.title3.bold()).lineLimit(1)
                Text([session.subject, session.started.formatted(date: .complete, time: .shortened),
                      session.duration.map(minutes)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 420)
            Menu {
                Button("PDF (with formulas)…") {
                    tab = .notes
                    exporter.exportPDF(named: session.title)
                }
                Button("Markdown…") { exportMarkdown(session) }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(12)
    }

    private var focusedNoteID: String? {
        guard let f = model.focusTime, let note = session.notes.last(where: { $0.time <= f }) ?? session.notes.first else {
            return nil
        }
        return String(Int(note.time * 1000))
    }

    private func seek(_ t: TimeInterval) {
        guard player.isAvailable else { return }
        player.play(from: max(0, t - 2)) // a beat of context before the moment
    }
}

private struct TranscriptView: View {
    let session: ClassSession
    @ObservedObject var player: LecturePlayer
    let seek: (TimeInterval) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            List(Array(session.segments.enumerated()), id: \.offset) { i, segment in
                let next = i + 1 < session.segments.count ? session.segments[i + 1].time : .infinity
                let playing = player.isPlaying && player.time >= segment.time && player.time < next
                let marks = (session.marks ?? []).filter { $0.time >= segment.time && $0.time < next }
                HStack(alignment: .top, spacing: 10) {
                    Button(clock(segment.time)) { seek(segment.time) }
                        .buttonStyle(.plain)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tint)
                        .frame(width: 48, alignment: .leading)
                    Text(segment.text).textSelection(.enabled)
                    Spacer(minLength: 0)
                    if !marks.isEmpty { Text(marks.map(\.kind.symbol).joined()) }
                }
                .padding(.vertical, 3)
                .listRowBackground(playing ? Color.accentColor.opacity(0.12) : Color.clear)
                .id(i)
            }
            .listStyle(.plain)
            .overlay {
                if session.segments.isEmpty { Text("No transcript yet.").foregroundStyle(.secondary) }
            }
        }
    }
}

private struct StudyView: View {
    let session: ClassSession
    @ObservedObject var model: ClassNotesModel

    var body: some View {
        if let pack = session.studyPack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Summary", "text.alignleft") { Text(pack.summary).textSelection(.enabled) }
                    if !pack.terms.isEmpty {
                        section("Key terms", "character.book.closed") {
                            ForEach(Array(pack.terms.enumerated()), id: \.offset) { _, t in
                                (Text(t.term).bold() + Text(" — " + t.meaning)).textSelection(.enabled)
                            }
                        }
                    }
                    if !pack.questions.isEmpty {
                        section("Practice questions", "questionmark.circle") {
                            ForEach(Array(pack.questions.enumerated()), id: \.offset) { i, q in
                                Text("\(i + 1). \(q)").textSelection(.enabled)
                            }
                        }
                    }
                    if !pack.todos.isEmpty {
                        section("To do", "checklist") {
                            ForEach(pack.todos, id: \.self) { Label($0, systemImage: "circle") }
                        }
                    }
                    let flagged = (session.marks ?? []).filter { $0.kind != .important }
                    if !flagged.isEmpty {
                        section("Moments you flagged", "flag") {
                            ForEach(Array(flagged.enumerated()), id: \.offset) { _, m in
                                Text("\(m.kind.symbol) \(m.kind.label) at \(clock(m.time))")
                            }
                        }
                    }
                    Button("Regenerate study pack") { model.makeStudyPack(for: session) }
                        .disabled(model.makingStudyPack != nil)
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "books.vertical").font(.system(size: 40)).foregroundStyle(.tint)
                Text("Study pack").font(.title2.bold())
                Text("A summary, key terms, practice questions, flashcards and to-dos — made from your notes on this Mac.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(width: 420)
                if model.makingStudyPack == session.id {
                    ProgressView("Making your study pack…")
                } else {
                    Button("Make study pack") { model.makeStudyPack(for: session) }
                        .buttonStyle(.borderedProminent)
                        .disabled(session.notes.isEmpty || model.ai() == nil)
                }
            }
        }
    }

    private func section(_ title: String, _ icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline)
            VStack(alignment: .leading, spacing: 6) { content() }
        }
    }
}

private struct FlashcardsView: View {
    let cards: [ClassSession.StudyPack.Card]
    let makePack: () -> Void
    let making: Bool
    @State private var index = 0
    @State private var flipped = false
    @State private var known: Set<Int> = []

    var body: some View {
        if cards.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.on.rectangle.angled").font(.system(size: 40)).foregroundStyle(.tint)
                Text("No flashcards yet").font(.title2.bold())
                if making { ProgressView("Making your study pack…") } else {
                    Button("Make flashcards", action: makePack).buttonStyle(.borderedProminent)
                }
            }
        } else {
            VStack(spacing: 20) {
                Text("Card \(index + 1) of \(cards.count) · \(known.count) known").foregroundStyle(.secondary)
                ZStack {
                    RoundedRectangle(cornerRadius: 20).fill(flipped ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                    VStack(spacing: 10) {
                        Text(flipped ? "Answer" : "Question").font(.caption.bold()).foregroundStyle(.secondary)
                        Text(flipped ? cards[index].back : cards[index].front)
                            .font(.title3).multilineTextAlignment(.center).padding(.horizontal, 30)
                    }
                }
                .frame(width: 520, height: 260)
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { flipped.toggle() } }
                Text("Click the card to flip").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Button { go(-1) } label: { Label("Back", systemImage: "chevron.left") }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Button { known.insert(index); go(1) } label: { Label("I knew it", systemImage: "checkmark") }
                        .keyboardShortcut("k", modifiers: [])
                    Button { known.remove(index); go(1) } label: { Label("Review again", systemImage: "arrow.clockwise") }
                    Button { go(1) } label: { Label("Next", systemImage: "chevron.right") }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                }
            }
        }
    }

    private func go(_ step: Int) {
        flipped = false
        index = (index + step + cards.count) % cards.count
    }
}

private struct AskView: View {
    let session: ClassSession
    let ai: ClassAI?
    let seek: (TimeInterval) -> Void
    @State private var question = ""
    @State private var answer: String?
    @State private var thinking = false

    private let suggestions = ["What were the main ideas?", "Explain the hardest part simply",
                               "What will likely be on the exam?", "Give me an example"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask about this lecture").font(.title3.bold())
            HStack {
                TextField("e.g. How does Bayes' theorem relate to conditional probability?", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(ask)
                Button("Ask", action: ask).buttonStyle(.borderedProminent).disabled(question.isEmpty || thinking || ai == nil)
            }
            HStack {
                ForEach(suggestions, id: \.self) { s in
                    Button(s) { question = s; ask() }.font(.caption).disabled(thinking || ai == nil)
                }
            }
            if ai == nil {
                Text("Download the notes model (start panel) to ask questions.").font(.caption).foregroundStyle(.secondary)
            }
            if thinking { ProgressView("Reading the lecture…") }
            if let answer {
                NotesWebView(items: [.init(id: "a", label: "Answer", text: answer, focused: false)], transcript: [], scrollTo: "a")
                    .frame(minHeight: 220)
            }
            Spacer()
        }
        .padding(24)
    }

    private func ask() {
        guard let ai, !question.isEmpty, !thinking else { return }
        thinking = true
        answer = nil
        // The most relevant stretches of the lecture, in time order, with their times.
        let texts = session.segments.map(\.text)
        let picked = SemanticSearch.rank(question, in: texts, limit: 18).sorted()
        let excerpts = (picked.isEmpty ? Array(session.segments.indices.prefix(18)) : picked)
            .map { "[\(clock(session.segments[$0].time))] \(session.segments[$0].text)" }.joined(separator: "\n")
        let q = question
        Task {
            answer = await ai.answer(q, excerpts) ?? "Couldn't answer that — try rephrasing."
            thinking = false
        }
    }
}

private struct PlayerBar: View {
    @ObservedObject var player: LecturePlayer
    let marks: [ClassSession.Mark]

    var body: some View {
        HStack(spacing: 12) {
            Button { player.skip(-15) } label: { Image(systemName: "gobackward.15") }.buttonStyle(.plain)
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 26))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            Button { player.skip(15) } label: { Image(systemName: "goforward.15") }.buttonStyle(.plain)
            Text(clock(player.time)).font(.caption.monospacedDigit()).frame(width: 44)
            ZStack(alignment: .leading) {
                Slider(value: Binding(get: { player.time }, set: { player.seek($0) }), in: 0 ... max(1, player.duration))
                GeometryReader { g in
                    ForEach(Array(marks.enumerated()), id: \.offset) { _, m in
                        Text(m.kind.symbol).font(.system(size: 10))
                            .position(x: g.size.width * CGFloat(m.time / max(1, player.duration)), y: -4)
                            .onTapGesture { player.play(from: max(0, m.time - 5)) }
                    }
                }
                .frame(height: 10)
            }
            Text(clock(player.duration)).font(.caption.monospacedDigit()).frame(width: 44)
            Picker("", selection: $player.rate) {
                Text("1×").tag(Float(1))
                Text("1.25×").tag(Float(1.25))
                Text("1.5×").tag(Float(1.5))
                Text("2×").tag(Float(2))
            }
            .labelsHidden()
            .frame(width: 80)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Helpers

@MainActor
private func noteItems(_ session: ClassSession, focusTime: TimeInterval?) -> [NotesWebView.Item] {
    session.notes.enumerated().map { i, note in
        let next = i + 1 < session.notes.count ? session.notes[i + 1].time : .infinity
        let focused = focusTime.map { $0 >= note.time && $0 < next } ?? false
        return NotesWebView.Item(id: String(Int(note.time * 1000)), label: clock(note.time), text: note.text,
                                 focused: focused, mine: note.mine == true, time: note.time)
    }
}

private func clock(_ t: TimeInterval) -> String {
    Duration.seconds(t).formatted(.time(pattern: t >= 3600 ? .hourMinuteSecond : .minuteSecond))
}

private func minutes(_ t: TimeInterval) -> String {
    "\(max(1, Int((t / 60).rounded()))) min"
}

@MainActor
private func exportMarkdown(_ session: ClassSession) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = session.title + ".md"
    panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
    if panel.runModal() == .OK, let url = panel.url {
        try? session.markdown().write(to: url, atomically: true, encoding: .utf8)
    }
}
