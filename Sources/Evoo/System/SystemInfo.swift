import Foundation

enum SystemInfo {
    static var memoryGB: Double { Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 }

    /// Smart cleanup keeps a ~2.5 GB model loaded next to the speech model; 16 GB Macs handle that comfortably.
    /// `defaults write app.evoo.Evoo allowSmartCleanupOnAnyMac -bool true` overrides this for testing.
    static var canRunSmartCleanup: Bool {
        memoryGB >= 15.5 || UserDefaults.standard.bool(forKey: "allowSmartCleanupOnAnyMac")
    }
}
