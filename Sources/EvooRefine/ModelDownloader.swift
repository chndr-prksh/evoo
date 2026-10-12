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
        public static let url = URL(string: "https://github.com/chndr-prksh/evoo/releases/download/tools-model-v1/evoo-tools-q8_0.gguf")!
        public static let sha256 = "65b69407aa8d249386aa4bbb5bede487e3ebc1350300f8ea95e14d54eb23d3d5"
        public static let sizeBytes: Int64 = 291_558_848
        public static var file: URL { ModelPaths.root.appendingPathComponent("tools/evoo-tools-q8_0.gguf") }
        public static var isInstalled: Bool { FileManager.default.fileExists(atPath: file.path) }
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
