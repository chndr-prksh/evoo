import AVFoundation
import Foundation

/// Plays a class recording from any moment ("click a note, hear that part of the lecture").
@MainActor
final class LecturePlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var time: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var rate: Float = 1 { didSet { player?.rate = rate } }

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private(set) var url: URL?

    func load(_ url: URL?) {
        guard url != self.url else { return }
        stop()
        self.url = url
        player = url.flatMap { try? AVAudioPlayer(contentsOf: $0) }
        player?.enableRate = true
        player?.prepareToPlay()
        duration = player?.duration ?? 0
        time = 0
    }

    var isAvailable: Bool { player != nil }

    func toggle() { isPlaying ? pause() : play() }

    func play(from t: TimeInterval? = nil) {
        guard let player else { return }
        if let t { player.currentTime = max(0, min(t, player.duration)) }
        player.rate = rate
        player.play()
        isPlaying = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player else { return }
                self.time = p.currentTime
                if !p.isPlaying { self.isPlaying = false; self.timer?.invalidate() }
            }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    func seek(_ t: TimeInterval) {
        player?.currentTime = max(0, min(t, duration))
        time = player?.currentTime ?? 0
    }

    func skip(_ delta: TimeInterval) { seek(time + delta) }

    func stop() {
        player?.stop()
        isPlaying = false
        timer?.invalidate()
    }
}
