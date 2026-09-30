import AVFoundation
import CoreAudio

/// Captures microphone audio as 16 kHz mono Float32 — the format every ASR engine expects.
final class AudioRecorder {
    static let sampleRate: Double = 16_000

    /// Called on the audio thread with a 0…1 level for the pill's waveform.
    var onLevel: ((Float) -> Void)?
    /// Called once per recording, on the audio thread, when the first audio arrives (to measure mic start).
    var onFirstAudio: (() -> Void)?
    private var gotAudio = false

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                             channels: 1, interleaved: false)!

    /// Recording for a dictation. Read by the audio thread, so behind `lock`.
    var isRecording: Bool { lock.withLock { recording } }
    private var recording = false
    /// "Keep the microphone ready": the mic runs between dictations and only the last `preRollSeconds` are kept
    /// (in memory, never processed), so a dictation starts instantly — including the moment just before fn.
    var inStandby: Bool { lock.withLock { standby } }
    private var standby = false
    private var preRoll: [Float] = []
    static let preRollSeconds = 0.3
    /// Called when macOS reset the audio engine (device change, sleep) while in standby.
    var onEngineReset: (() -> Void)?
    private var resetObserver: NSObjectProtocol?

    /// Creates the audio input ahead of time (without turning the microphone on), so the first fn press doesn't
    /// pay for it — that can take 0.3–4 s on a busy Mac.
    func warmUp() {
        guard !isRecording else { return }
        let input = engine.inputNode
        _ = input.outputFormat(forBus: 0)
    }

    /// Starts the mic without recording (see `inStandby`).
    func startStandby(deviceUID: String?) throws {
        guard !inStandby, !isRecording else { return }
        try startEngine(deviceUID: deviceUID)
        lock.withLock {
            standby = true
            preRoll.removeAll(keepingCapacity: true)
        }
        if resetObserver == nil {
            resetObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
                self?.onEngineReset?()
            }
        }
    }

    /// Turns the mic off again (unless a dictation is using it — then it stops when the dictation ends).
    func stopStandby() {
        let wasRecording = lock.withLock { () -> Bool in
            standby = false
            preRoll.removeAll()
            return recording
        }
        guard !wasRecording, engine.isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.prepare()
    }

    /// After a device change or sleep: the engine stopped; start standby again.
    func restartStandby(deviceUID: String?) {
        guard inStandby, !isRecording else { return }
        stopStandby()
        try? startStandby(deviceUID: deviceUID)
    }

    private func startEngine(deviceUID: String?) throws {
        let input = engine.inputNode
        if let uid = deviceUID, let id = AudioDevices.deviceID(forUID: uid), let unit = input.audioUnit {
            var deviceID = id
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw RecorderError.noInputDevice }
        converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func start(deviceUID: String?) throws {
        guard !isRecording else { return }
        gotAudio = false
        let warm = lock.withLock { () -> Bool in
            // In standby the mic is already live: start from the audio just before fn went down.
            samples = standby ? preRoll : []
            preRoll.removeAll(keepingCapacity: true)
            return standby
        }
        if !warm { try startEngine(deviceUID: deviceUID) }
        lock.withLock { recording = true }
    }

    /// Hands over what was recorded since the last call and forgets it — for long recordings (class notes).
    func take() -> [Float] {
        lock.withLock {
            let out = samples
            samples.removeAll(keepingCapacity: true)
            return out
        }
    }

    /// Everything recorded so far, while still recording (for speculative transcription).
    func snapshot() -> [Float] {
        lock.withLock { samples }
    }

    var sampleCount: Int { lock.withLock { samples.count } }

    /// What was recorded from sample `index` on (cheap: doesn't copy the whole recording).
    func snapshot(from index: Int) -> [Float] {
        lock.withLock { index < samples.count ? Array(samples[index...]) : [] }
    }

    /// Stops capture and returns everything recorded since `start`.
    func stop() -> [Float] {
        let samples = detach()
        shutDown()
        return samples
    }

    /// Stops collecting audio and returns it — fast. In standby the mic keeps running for the next dictation.
    func detach() -> [Float] {
        let (was, keep, out) = lock.withLock { () -> (Bool, Bool, [Float]) in
            let was = recording
            recording = false
            return (was, standby, samples)
        }
        guard was else { return [] }
        if !keep { engine.inputNode.removeTap(onBus: 0) }
        return out
    }

    /// Stops the audio engine (can take 100+ ms) and pre-allocates for the next start — unless in standby.
    func shutDown() {
        guard !isRecording, !inStandby, engine.isRunning else { return }
        engine.stop()
        engine.prepare()
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.floatChannelData?[0] else { return }
        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        let isRecording = lock.withLock { () -> Bool in
            if recording {
                samples.append(contentsOf: chunk)
            } else if standby {
                // Between dictations: keep only the last moment, for the next fn press.
                preRoll.append(contentsOf: chunk)
                let keep = Int(Self.preRollSeconds * Self.sampleRate)
                if preRoll.count > keep { preRoll.removeFirst(preRoll.count - keep) }
            }
            return recording
        }
        guard isRecording else { return }
        if !gotAudio {
            gotAudio = true
            onFirstAudio?()
        }

        var sum: Float = 0
        for s in chunk { sum += s * s }
        let rms = chunk.isEmpty ? 0 : (sum / Float(chunk.count)).squareRoot()
        // Loudness in dB mapped to 0…1: room noise (≈ -50 dB) is flat, normal speech (-35…-20 dB) fills the bars.
        let db = 20 * log10(max(rms, 1e-6))
        onLevel?(min(1, max(0, (db + 50) / 30)))
    }

    enum RecorderError: LocalizedError {
        case noInputDevice
        var errorDescription: String? { "No microphone available." }
    }
}

/// Lists CoreAudio input devices for the microphone picker.
enum AudioDevices {
    struct Device: Identifiable, Hashable {
        let id: String // UID, stable across reboots
        let name: String
    }

    static func inputs() -> [Device] {
        allDeviceIDs().compactMap { id in
            guard hasInput(id), let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return Device(id: uid, name: name)
        }
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        allDeviceIDs().first { string($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let list = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { list.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, list) == noErr else { return false }
        let buffers = UnsafeMutableAudioBufferListPointer(list.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
