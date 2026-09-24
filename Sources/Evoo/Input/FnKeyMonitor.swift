import AppKit
import EvooCore

/// Watches the Fn/Globe key system-wide with a listen-only CGEventTap.
/// Requires Input Monitoring permission. Never swallows events.
final class FnKeyMonitor {
    enum Event {
        case fnDown, fnUp, otherKey, escape, returnKey
    }

    private static let fnKeyCode: Int64 = 63 // kVK_Function
    private static let escapeKeyCode: Int64 = 53 // kVK_Escape
    private static let returnKeyCodes: Set<Int64> = [36, 76] // kVK_Return, kVK_ANSI_KeypadEnter

    var onEvent: ((Event) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var fnIsDown = false

    var isRunning: Bool { tap != nil }

    /// Returns false when Input Monitoring hasn't been granted yet.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else { return false }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        fnIsDown = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables slow taps; turn it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == Self.fnKeyCode {
                let down = event.flags.contains(.maskSecondaryFn)
                guard down != fnIsDown else { return }
                fnIsDown = down
                onEvent?(down ? .fnDown : .fnUp)
            } else if fnIsDown {
                onEvent?(.otherKey) // Fn + another modifier
            }
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == Self.escapeKeyCode {
                onEvent?(.escape)
            } else if Self.returnKeyCodes.contains(keyCode), !fnIsDown {
                onEvent?(.returnKey)
            } else if fnIsDown {
                onEvent?(.otherKey) // Fn+arrow, Fn+F-key, …
            }
        default:
            break
        }
    }
}
