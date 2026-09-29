import EvooCore
import Foundation

/// Classes are saved on this Mac: ~/Library/Application Support/Evoo/Classes/<id>/session.json.
@MainActor
final class ClassStore: ObservableObject {
    static let shared = ClassStore()

    @Published private(set) var sessions: [ClassSession] = []
    let root = ModelPaths.root.deletingLastPathComponent().appendingPathComponent("Classes", isDirectory: true)

    private init() { reload() }

    func reload() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        sessions = dirs.compactMap { dir in
            (try? Data(contentsOf: dir.appendingPathComponent("session.json")))
                .flatMap { try? JSONDecoder().decode(ClassSession.self, from: $0) }
        }
        .sorted { $0.started > $1.started }
    }

    func folder(for session: ClassSession) -> URL { root.appendingPathComponent(session.id.uuidString, isDirectory: true) }

    func save(_ session: ClassSession) {
        let dir = folder(for: session)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(session).write(to: dir.appendingPathComponent("session.json"), options: .atomic)
        if let i = sessions.firstIndex(where: { $0.id == session.id }) { sessions[i] = session } else {
            sessions.insert(session, at: 0)
        }
    }

    func delete(_ session: ClassSession) {
        try? FileManager.default.removeItem(at: folder(for: session))
        sessions.removeAll { $0.id == session.id }
    }
}
