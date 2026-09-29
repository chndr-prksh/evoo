import EvooCore
import Foundation

/// The user's recent dictations, kept only on this Mac (~/Library/Application Support/Evoo/history.json)
/// so they can search and re-use them. Capped, can be turned off, and cleared from Settings.
@MainActor
final class DictationHistory: ObservableObject {
    struct Entry: Codable, Identifiable, Hashable {
        var id = UUID()
        var date: Date
        var app: String?
        var text: String
    }

    static let shared = DictationHistory(file: "history.json", limit: 500)
    /// Voice notes ("note: …") — same storage, kept separately and for longer.
    static let notes = DictationHistory(file: "notes.json", limit: 5_000)

    @Published private(set) var entries: [Entry] = []
    private let file: URL
    private let limit: Int

    private init(file name: String, limit: Int) {
        file = ModelPaths.root.deletingLastPathComponent().appendingPathComponent(name)
        self.limit = limit
        entries = (try? JSONDecoder().decode([Entry].self, from: Data(contentsOf: file))) ?? []
    }

    func add(_ text: String, app: String?) {
        entries.insert(Entry(date: Date(), app: app, text: text), at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: file, options: .atomic)
    }
}
