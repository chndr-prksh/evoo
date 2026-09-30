import CryptoKit
import EvooCore
import Foundation

/// The optional Hinglish speech model: Oriserve/Whisper-Hindi2Hinglish-Swift (Apache-2.0), converted to Core ML,
/// with its tokenizer. Downloaded from Settings (133 MB), checked against a pinned SHA-256, used only when the
/// dictation language is Hinglish — English keeps its own model and pipeline.
public enum HinglishAddon {
    public static let name = "evoo-hinglish-small-v1"
    public static let url = URL(string: "https://github.com/chndr-prksh/evoo/releases/download/hinglish-small-v1/evoo-hinglish-small-v1.zip")!
    public static let sha256 = "6b925258547398f605d9c50be2a28a7574f6f74b52f9c1a1c8a164e2ced0a8d2"
    public static let sizeMB = 133

    public static var base: URL { ModelPaths.root.appendingPathComponent("hinglish", isDirectory: true) }
    public static var folder: URL { base.appendingPathComponent(name, isDirectory: true) }
    public static var tokenizerFolder: URL { folder.appendingPathComponent("tokenizer", isDirectory: true) }

    public static var isInstalled: Bool {
        ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"].allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }

    public static func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let delegate = ProgressDelegate(progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (temp, _) = try await session.download(from: url)
        let digest = try SHA256.hash(data: Data(contentsOf: temp, options: .mappedIfSafe))
            .map { String(format: "%02x", $0) }.joined()
        guard digest == sha256 else {
            try? fm.removeItem(at: temp)
            throw NSError(domain: "Evoo", code: 1, userInfo: [NSLocalizedDescriptionKey: "The Hinglish model download was corrupted — try again."])
        }
        try? fm.removeItem(at: folder)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", temp.path, base.path]
        try unzip.run()
        unzip.waitUntilExit()
        try? fm.removeItem(at: temp)
        guard unzip.terminationStatus == 0, isInstalled else {
            throw NSError(domain: "Evoo", code: 2, userInfo: [NSLocalizedDescriptionKey: "Couldn't unpack the Hinglish model."])
        }
        progress(1)
    }

    public static func remove() {
        try? FileManager.default.removeItem(at: base)
    }

    private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let report: @Sendable (Double) -> Void
        init(_ report: @escaping @Sendable (Double) -> Void) { self.report = report }
        func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask, didWriteData _: Int64,
                        totalBytesWritten written: Int64, totalBytesExpectedToWrite total: Int64) {
            if total > 0 { report(Double(written) / Double(total) * 0.98) }
        }
        func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask, didFinishDownloadingTo _: URL) {}
    }
}
