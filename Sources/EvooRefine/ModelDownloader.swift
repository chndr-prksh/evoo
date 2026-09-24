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
        let destination = ModelPaths.refiner(model)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)

        let tempURL: URL = try await withCheckedThrowingContinuation { cont in
            let task = URLSession.shared.downloadTask(with: model.downloadURL) { url, response, error in
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

        guard try sha256(of: tempURL) == model.sha256 else {
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
