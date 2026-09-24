import Foundation

/// How the Fn key starts and stops dictation.
public enum ActivationMode: String, CaseIterable, Codable, Sendable {
    /// Hold Fn to talk, release to finish. Double-tap Fn for hands-free; tap again to finish.
    case hybrid
    /// Hold Fn to talk, release to finish.
    case hold
    /// Double-tap Fn to start, tap once to finish.
    case toggle

    public var title: String {
        switch self {
        case .hybrid: "Hold or double-tap"
        case .hold: "Hold to talk"
        case .toggle: "Double-tap to toggle"
        }
    }
}

public enum HotkeyInput: Equatable, Sendable {
    case fnDown(at: TimeInterval)
    case fnUp(at: TimeInterval)
    /// Any other key or modifier while Fn is involved (Fn+arrow, Fn+F5, …).
    case otherKey(at: TimeInterval)
}

public enum HotkeyAction: Equatable, Sendable {
    case start
    case stop
    case cancel
}

/// Pure state machine turning raw Fn events into start/stop/cancel.
/// Contains no timers: the owner calls `timeout(now:)` shortly after `pendingDeadline`.
public struct HotkeyGesture: Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        /// Toggle mode: one tap seen, waiting for the second.
        case armed(firstTapAt: TimeInterval)
        /// Recording while Fn is held.
        case holding(since: TimeInterval)
        /// Hybrid mode: a short tap; recording provisionally, waiting to see if it's a double-tap.
        case tapPending(releasedAt: TimeInterval)
        /// Hands-free recording. `awaitingRelease` swallows the key-up of the tap that latched.
        case latched(awaitingRelease: Bool)
    }

    public var mode: ActivationMode
    public var doubleTapWindow: TimeInterval = 0.35
    /// Holds shorter than this are treated as taps (hybrid) or accidental presses (hold).
    public var minHold: TimeInterval = 0.25
    public private(set) var phase: Phase = .idle

    public init(mode: ActivationMode) {
        self.mode = mode
    }

    public var isRecording: Bool {
        switch phase {
        case .holding, .tapPending, .latched: true
        case .idle, .armed: false
        }
    }

    /// When the owner should call `timeout(now:)`, if anything is pending.
    public var pendingDeadline: TimeInterval? {
        switch phase {
        case let .armed(t): t + doubleTapWindow
        case let .tapPending(t): t + doubleTapWindow
        default: nil
        }
    }

    public mutating func reset() {
        phase = .idle
    }

    public mutating func handle(_ input: HotkeyInput) -> HotkeyAction? {
        switch mode {
        case .hold: handleHold(input)
        case .toggle: handleToggle(input)
        case .hybrid: handleHybrid(input)
        }
    }

    public mutating func timeout(now: TimeInterval) -> HotkeyAction? {
        guard let deadline = pendingDeadline, now >= deadline else { return nil }
        switch phase {
        case .armed:
            phase = .idle
            return nil
        case .tapPending:
            // A single short tap in hybrid mode: accidental, discard.
            phase = .idle
            return .cancel
        default:
            return nil
        }
    }

    // MARK: - Modes

    private mutating func handleHold(_ input: HotkeyInput) -> HotkeyAction? {
        switch (phase, input) {
        case let (.idle, .fnDown(t)):
            phase = .holding(since: t)
            return .start
        case let (.holding(since), .fnUp(t)):
            phase = .idle
            return t - since < minHold ? .cancel : .stop
        case (.holding, .otherKey):
            phase = .idle
            return .cancel
        default:
            return nil
        }
    }

    private mutating func handleToggle(_ input: HotkeyInput) -> HotkeyAction? {
        switch (phase, input) {
        case let (.idle, .fnDown(t)):
            phase = .armed(firstTapAt: t)
            return nil
        case let (.armed(first), .fnDown(t)):
            if t - first <= doubleTapWindow {
                phase = .latched(awaitingRelease: true)
                return .start
            }
            phase = .armed(firstTapAt: t)
            return nil
        case (.armed, .otherKey):
            phase = .idle
            return nil
        default:
            return handleLatched(input)
        }
    }

    private mutating func handleHybrid(_ input: HotkeyInput) -> HotkeyAction? {
        switch (phase, input) {
        case let (.idle, .fnDown(t)):
            // Start immediately so the first words are never clipped.
            phase = .holding(since: t)
            return .start
        case let (.holding(since), .fnUp(t)):
            if t - since >= minHold {
                phase = .idle
                return .stop
            }
            phase = .tapPending(releasedAt: t)
            return nil
        case (.holding, .otherKey), (.tapPending, .otherKey):
            phase = .idle
            return .cancel
        case let (.tapPending(released), .fnDown(t)):
            if t - released <= doubleTapWindow {
                phase = .latched(awaitingRelease: true)
                return nil // already recording
            }
            phase = .holding(since: t)
            return .start
        default:
            return handleLatched(input)
        }
    }

    private mutating func handleLatched(_ input: HotkeyInput) -> HotkeyAction? {
        switch (phase, input) {
        case (.latched(true), .fnUp):
            phase = .latched(awaitingRelease: false)
            return nil
        case (.latched(false), .fnDown):
            phase = .idle
            return .stop
        default:
            return nil
        }
    }
}
