import EvooCore
import Foundation

/// Your edit pairs ("what Evoo typed → what you sent"), kept only on this Mac in
/// ~/Library/Application Support/Evoo/style-pairs.json. Used to write the way you do (in the polish prompt), and
/// later to fine-tune a personal model. Erase from Settings › Learning.
@MainActor
final class StyleStore: ObservableObject {
    static let shared = StyleStore()
    static let capacity = 3_000

    @Published private(set) var pairs: [StylePair] = [] { didSet { rewrites = StyleRewrites.learn(pairs) } }
    /// Word swaps learned per app ("going to" → "gonna"), applied to every dictation in that app.
    private(set) var rewrites: [String: [StyleRewrite]] = [:]
    let url = ModelPaths.root.deletingLastPathComponent().appendingPathComponent("style-pairs.json")

    init() {
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([StylePair].self, from: data) {
            pairs = saved
        }
        rewrites = StyleRewrites.learn(pairs)
    }

    var editedCount: Int { pairs.filter(\.edited).count }

    func add(_ pair: StylePair) {
        guard PersonalStyle.isUsable(pair) else { return }
        pairs.append(pair)
        if pairs.count > Self.capacity { pairs.removeFirst(pairs.count - Self.capacity) }
        save()
    }

    func erase() {
        pairs = []
        try? FileManager.default.removeItem(at: url)
    }

    /// Per-app style summaries, for Settings.
    var profiles: [(app: String, summary: String)] {
        Set(pairs.map(\.app)).sorted().compactMap { app in
            PersonalStyle.profile(app: app, pairs: pairs)?.summary.map { (app, $0) }
        }
    }

    private func save() {
        let snapshot = pairs
        let url = url
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
