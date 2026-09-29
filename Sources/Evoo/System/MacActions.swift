import AppKit
import AVFoundation
import Carbon.HIToolbox
import EvooCore

/// Carries out Mac voice commands: keys, Spotlight, Apple Shortcuts, volume and media, dark mode,
/// window layout, and clicking buttons by name (through the Accessibility permission Evoo already has).
@MainActor
enum MacActions {
    // MARK: - Keys

    static func press(_ combo: KeyCombo) -> Bool {
        guard let code = keyCodes[combo.key] else { return false }
        var flags: CGEventFlags = []
        if combo.command { flags.insert(.maskCommand) }
        if combo.shift { flags.insert(.maskShift) }
        if combo.option { flags.insert(.maskAlternate) }
        if combo.control { flags.insert(.maskControl) }
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
        return true
    }

    /// ANSI (US) layout key codes.
    static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "=": kVK_ANSI_Equal, "-": kVK_ANSI_Minus, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
        ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash,
        "return": kVK_Return, "tab": kVK_Tab, "space": kVK_Space, "delete": kVK_Delete,
        "forwarddelete": kVK_ForwardDelete, "escape": kVK_Escape, "left": kVK_LeftArrow, "right": kVK_RightArrow,
        "up": kVK_UpArrow, "down": kVK_DownArrow, "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp,
        "pagedown": kVK_PageDown, "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5,
        "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    ]

    // MARK: - Spotlight & Shortcuts

    /// ⌘Space, then types the query into Spotlight.
    static func spotlight(_ query: String, injector: TextInjector) async {
        _ = press(KeyCombo("space", command: true))
        try? await Task.sleep(for: .milliseconds(350)) // let Spotlight open
        await injector.insert(query, restoreClipboard: true)
    }

    /// Runs an Apple Shortcut by name with the built-in `shortcuts` tool. Returns an error message on failure.
    static func runShortcut(_ name: String) async -> String? {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            p.arguments = ["run", name]
            let err = Pipe()
            p.standardError = err
            do { try p.run() } catch { return "Couldn't run Shortcuts" }
            p.waitUntilExit()
            return p.terminationStatus == 0 ? nil : "No shortcut named “\(name)”"
        }.value
    }

    // MARK: - Sound, media, appearance

    static func setVolume(_ percent: Int) { osascript("set volume output volume \(percent)") }

    static func stepVolume(up: Bool) {
        osascript("set volume output volume ((output volume of (get volume settings)) \(up ? "+" : "-") 10)")
    }

    static func mute(_ on: Bool) { osascript("set volume output muted \(on)") }

    /// macOS asks once for permission to control System Events.
    static func darkMode(_ on: Bool) {
        osascript("tell application \"System Events\" to tell appearance preferences to set dark mode to \(on)")
    }

    static func media(_ key: MacCommand.Media) {
        let code: Int32 = switch key {
        case .playPause: NX_KEYTYPE_PLAY
        case .next: NX_KEYTYPE_NEXT
        case .previous: NX_KEYTYPE_PREVIOUS
        }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((code << 16) | ((down ? 0xA : 0xB) << 8))
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                               windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }

    private static func osascript(_ source: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        try? p.run()
    }

    // MARK: - Windows & clicking

    static func window(_ action: WindowAction) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, let screen = NSScreen.main else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return false }
        let window = raw as! AXUIElement
        switch action {
        case .fullScreen:
            return AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanTrue) == .success
        case .minimize:
            return AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
        default: break
        }
        // Accessibility uses top-left-origin screen coordinates.
        let v = screen.visibleFrame
        let top = (NSScreen.screens.first?.frame.maxY ?? v.maxY) - v.maxY
        var frame = CGRect(x: v.minX, y: top, width: v.width, height: v.height)
        switch action {
        case .leftHalf: frame.size.width /= 2
        case .rightHalf: frame.size.width /= 2; frame.origin.x += frame.width
        case .topHalf: frame.size.height /= 2
        case .bottomHalf: frame.size.height /= 2; frame.origin.y += frame.height
        case .center: frame = frame.insetBy(dx: v.width * 0.15, dy: v.height * 0.1)
        default: break
        }
        var origin = frame.origin, size = frame.size
        guard let pos = AXValueCreate(.cgPoint, &origin), let sz = AXValueCreate(.cgSize, &size) else { return false }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pos)
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sz) == .success
    }

    /// Finds a button (or link, tab, checkbox, menu item) by its visible name in the front window and presses it.
    static func click(_ label: String) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        ScreenText.enableWebAccessibility(for: app.processIdentifier)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return false }
        let target = label.lowercased()
        let pressable: Set<String> = ["AXButton", "AXLink", "AXMenuItem", "AXCheckBox", "AXRadioButton", "AXTab",
                                      "AXPopUpButton", "AXMenuButton", "AXDisclosureTriangle"]
        var queue = [raw as! AXUIElement]
        var partial: AXUIElement?
        var visited = 0
        while !queue.isEmpty, visited < 4_000 {
            let node = queue.removeFirst()
            visited += 1
            let role = string(node, kAXRoleAttribute) ?? ""
            if pressable.contains(role) {
                let names = [kAXTitleAttribute, kAXDescriptionAttribute, "AXHelp", kAXValueAttribute]
                    .compactMap { string(node, $0)?.lowercased() }
                if names.contains(target) {
                    return AXUIElementPerformAction(node, kAXPressAction as CFString) == .success
                }
                if partial == nil, names.contains(where: { $0.contains(target) }) { partial = node }
            }
            var kids: CFTypeRef?
            if AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &kids) == .success,
               let list = kids as? [AXUIElement]
            {
                queue.append(contentsOf: list)
            }
        }
        if let partial { return AXUIElementPerformAction(partial, kAXPressAction as CFString) == .success }
        return false
    }

    private static func string(_ el: AXUIElement, _ attribute: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attribute as CFString, &v) == .success else { return nil }
        return v as? String
    }
}
