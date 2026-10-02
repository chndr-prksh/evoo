import AppKit
import AVFoundation
import ServiceManagement

/// The three macOS permissions Evoo needs, and where to grant them.
@MainActor
final class Permissions: ObservableObject {
    enum Kind: CaseIterable, Identifiable {
        case microphone, inputMonitoring, accessibility
        var id: Self { self }

        var title: String {
            switch self {
            case .microphone: "Microphone"
            case .inputMonitoring: "Input Monitoring"
            case .accessibility: "Accessibility"
            }
        }

        var reason: String {
            switch self {
            case .microphone: "Hear your voice."
            case .inputMonitoring: "Detect the Fn key."
            case .accessibility: "Paste text into the app you're using."
            }
        }

        var settingsURL: URL {
            let anchor = switch self {
            case .microphone: "Privacy_Microphone"
            case .inputMonitoring: "Privacy_ListenEvent"
            case .accessibility: "Privacy_Accessibility"
            }
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        }
    }

    @Published private(set) var granted: [Kind: Bool] = [:]

    var allGranted: Bool { Kind.allCases.allSatisfy { granted[$0] == true } }

    func refresh() {
        granted = [
            .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            .inputMonitoring: CGPreflightListenEventAccess(),
            .accessibility: AXIsProcessTrusted(),
        ]
    }

    func request(_ kind: Kind) {
        switch kind {
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    Task { @MainActor in self.refresh() }
                }
                return
            }
        case .inputMonitoring:
            if CGRequestListenEventAccess() { return refresh() }
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            if AXIsProcessTrustedWithOptions(options) { return refresh() }
        }
        NSWorkspace.shared.open(kind.settingsURL)
    }
}

/// "Start at login". Asking macOS for the status is a round trip to a system service that can take ~1 s (after
/// sleep, on a busy Mac), so views read a cached value and `refresh()` updates it in the background.
enum LoginItem {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached = false

    static var isEnabled: Bool { lock.withLock { cached } }

    /// Asks macOS (off the main thread) and returns the up-to-date status.
    @discardableResult
    static func refresh() async -> Bool {
        await Task.detached(priority: .utility) {
            let on = SMAppService.mainApp.status == .enabled
            lock.withLock { cached = on }
            return on
        }.value
    }

    static func set(_ enabled: Bool) throws {
        defer { Task { await refresh() } }
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        lock.withLock { cached = enabled }
    }
}
