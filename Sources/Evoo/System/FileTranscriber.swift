import AppKit
import AVFoundation
import EvooCore
import EvooSpeech
import FluidAudio

/// Transcribes an audio or video file on this Mac: saves <name>.txt and <name>.srt (subtitles) next to it
/// (or in Downloads if that folder isn't writable) and shows them in Finder.
@MainActor
enum FileTranscriber {
    static func pickAndTranscribe(onStatus: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Movie, .quickTimeMovie, .mp3, .wav, .aiff]
        panel.message = "Choose an audio or video file to transcribe"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await transcribe(url, onStatus: onStatus) }
    }

    static func transcribe(_ url: URL, onStatus: @escaping (String) -> Void) async {
        onStatus("Transcribing \(url.lastPathComponent)…")
        do {
            let audio = try await extractAudio(url)
            let samples = try AudioConverter().resampleAudioFile(audio)
            let engine = ParakeetEngine()
            try await engine.load { _ in }
            let (text, timings) = try await engine.transcribeDetailed(samples)
            await engine.unload()

            let base = url.deletingPathExtension().lastPathComponent
            var folder = url.deletingLastPathComponent()
            if !FileManager.default.isWritableFile(atPath: folder.path) {
                folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            }
            let txt = folder.appendingPathComponent(base + ".txt")
            let srt = folder.appendingPathComponent(base + ".srt")
            try text.write(to: txt, atomically: true, encoding: .utf8)
            try Subtitles.srt(timings).write(to: srt, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([txt, srt])
            onStatus("Transcribed \(url.lastPathComponent)")
        } catch {
            onStatus("Couldn't transcribe \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Video files: pull out the audio track first (audio files are used as they are).
    private static func extractAudio(_ url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let hasVideo = !(try await asset.loadTracks(withMediaType: .video)).isEmpty
        guard hasVideo else { return url }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        export.outputURL = out
        export.outputFileType = .m4a
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { done.resume() }
        }
        guard export.status == .completed else { throw export.error ?? CocoaError(.fileWriteUnknown) }
        return out
    }
}
