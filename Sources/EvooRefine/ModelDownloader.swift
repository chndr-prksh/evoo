import CryptoKit
import EvooCore
import Foundation

/// Downloads a pinned GGUF from Hugging Face and verifies its SHA-256.
/// This is the only network access Evoo makes, and only when the user asks for a model.
public enum ModelDownloader {
    public static func isInstalled(_ model: RefinerModel) -> Bool {
        let url = ModelPaths.refiner(model)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
        return size == model.sizeBytes
    }

    public static func download(_ model: RefinerModel, progress: @escaping @Sendable (Double) -> Void) async throws {
        try await download(from: model.downloadURL, to: ModelPaths.refiner(model), sha256: model.sha256, progress: progress)
    }

    /// Evoo's tool-calling model (FunctionGemma 270M, fine-tuned on Evoo's tools): an optional 290 MB download.
    public enum Tools {
        /// v2 (36 tools, alarms included). The app's tool list (ToolCall.toolNames) must match the model's training.
        public static let url = URL(string: "https://github.com/chndr-prksh/evoo/releases/download/tools-model-v2/evoo-tools-v2-q8_0.gguf")!
        public static let sha256 = "2ebf241c2ee813cef42bebb0eb3648b57fc0ece2173d299fc05d0f5d1fbcc78b"
        public static let sizeBytes: Int64 = 291_558_848
        public static var file: URL { ModelPaths.root.appendingPathComponent("tools/evoo-tools-v2-q8_0.gguf") }
        public static var isInstalled: Bool { FileManager.default.fileExists(atPath: file.path) }
        /// v1, trained on the older tool list: never used, and removed once v2 is in place.
        public static var oldFile: URL { ModelPaths.root.appendingPathComponent("tools/evoo-tools-q8_0.gguf") }
        /// The previous model is on this Mac but not the current one: Settings offers the update.
        public static var updateAvailable: Bool { !isInstalled && FileManager.default.fileExists(atPath: oldFile.path) }
    }

    /// Downloads a file, checks it is exactly the expected one, then puts it in place.
    public static func download(from source: URL, to destination: URL, sha256 expected: String,
                                progress: @escaping @Sendable (Double) -> Void) async throws
    {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)

        let tempURL: URL = try await withCheckedThrowingContinuation { cont in
            let task = URLSession.shared.downloadTask(with: source) { url, response, error in
                if let error { return cont.resume(throwing: error) }
                guard let url, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    return cont.resume(throwing: URLError(.badServerResponse))
                }
                // The file is deleted when this handler returns; move it somewhere we own.
                let kept = destination.appendingPathExtension("part")
                try? FileManager.default.removeItem(at: kept)
                do {
                    try FileManager.default.moveItem(at: url, to: kept)
                    cont.resume(returning: kept)
                } catch {
                    cont.resume(throwing: error)
                }
            }
            let observation = task.progress.observe(\.fractionCompleted) { p, _ in progress(p.fractionCompleted) }
            objc_setAssociatedObject(task, "evoo.progress", observation, .OBJC_ASSOCIATION_RETAIN)
            task.resume()
        }

        guard try sha256(of: tempURL) == expected else {
            try? FileManager.default.removeItem(at: tempURL)
            throw DownloadError.checksumMismatch
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public enum DownloadError: LocalizedError {
        case checksumMismatch
        public var errorDescription: String? { "Downloaded model failed verification." }
    }
}
