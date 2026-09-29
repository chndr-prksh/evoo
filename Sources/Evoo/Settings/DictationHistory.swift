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

    static let shared = DictationHistory()
    private static let limit = 500

    @Published private(set) var entries: [Entry] = []
    private let file = ModelPaths.root.deletingLastPathComponent().appendingPathComponent("history.json")

    private init() {
        entries = (try? JSONDecoder().decode([Entry].self, from: Data(contentsOf: file))) ?? []
    }

    func add(_ text: String, app: String?) {
        entries.insert(Entry(date: Date(), app: app, text: text), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
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
