import EvooCore
import Foundation

/// Every step of each dictation, so a wrong result can be traced to the step that caused it: what the pill
/// showed, Parakeet's final transcript, Evoo's rules, the AI polish, what was typed, and what you changed it to.
/// Kept only on this Mac (~/Library/Application Support/Evoo/dictation-log.jsonl, one dictation per line),
/// off unless turned on in Settings, capped, and cleared from Settings.
@MainActor
final class DictationLog: ObservableObject {
    struct Entry: Codable {
        var id = UUID()
        var date = Date()
        var app: String?
        var language: String
        /// The polish model, when the AI ran on this dictation.
        var model: String?
        /// The last text the pill showed while you spoke.
        var heard: String
        /// Parakeet's final transcript, made when you let go.
        var transcript: String
        /// After Evoo's rules (fillers, corrections, numbers, formatting).
        var rules: String
        /// After the AI polish, when it ran.
        var polished: String?
        /// What Evoo typed, after per-app habits and learned word swaps.
        var typed: String
        /// What the text box held after your edits, when Evoo could read it back.
        var edited: String?
        /// Names from the screen that replaced words in this dictation.
        var screenNames: [String] = []
        var asrMs: Int
        var rulesMs: Int
        var polishMs: Int
    }

    static let shared = DictationLog()

    @Published private(set) var entries: [Entry] = []
    private let file: URL
    private let limit = 2_000

    private init() {
        file = ModelPaths.root.deletingLastPathComponent().appendingPathComponent("dictation-log.jsonl")
        let lines = (try? String(contentsOf: file, encoding: .utf8))?.split(separator: "\n") ?? []
        entries = lines.compactMap { try? JSONDecoder.log.decode(Entry.self, from: Data($0.utf8)) }
    }

    var fileURL: URL { file }

    func add(_ entry: Entry) {
        entries.append(entry)
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
        save()
    }

    /// What the user ended up with after editing a dictation (see `EditWatcher.onPair`).
    func noteEdit(inserted: String, final: String, app: String) {
        guard let i = entries.indices.suffix(5).last(where: { entries[$0].typed == inserted && entries[$0].app == app })
        else { return }
        entries[i].edited = final
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lines = entries.compactMap { try? JSONEncoder.log.encode($0) }.map { String(decoding: $0, as: UTF8.self) }
        try? (lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).write(to: file, atomically: true, encoding: .utf8)
    }
}

private extension JSONEncoder {
    static let log: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()
}

private extension JSONDecoder {
    static let log: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
