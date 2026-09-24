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

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
