import Foundation

enum SystemInfo {
    static var memoryGB: Double { Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 }

    /// Local AI features run on every Mac — quality first. Below 16 GB they're slower (seconds, not instant).
    static var canRunSmartCleanup: Bool { true }

    static var isLowMemory: Bool { memoryGB < 15.5 }
}
