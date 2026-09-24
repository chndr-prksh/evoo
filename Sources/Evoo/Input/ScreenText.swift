import AppKit

/// Reads visible text from the focused window through the Accessibility API (the permission Evoo already has
/// for pasting): window title, labels, chat headers, recipients, and the text around the cursor.
/// Used only to spot names for the current dictation; nothing is stored. Password fields are skipped.
enum ScreenText {
    static func capture(maxElements: Int = 1_500, budget: TimeInterval = 0.25) -> [String] {
        let deadline = Date().addingTimeInterval(budget)
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)
        guard let app: AXUIElement = element(system, kAXFocusedApplicationAttribute) else { return [] }
        AXUIElementSetMessagingTimeout(app, 0.05)
        var pid: pid_t = 0
        if AXUIElementGetPid(app, &pid) == .success { enableWebAccessibility(for: pid) }

        var texts: [String] = []
        if let focused: AXUIElement = element(app, kAXFocusedUIElementAttribute), !isSecure(focused),
           let value: String = attribute(focused, kAXValueAttribute)
        {
            texts.append(String(value.suffix(4_000))) // what you're replying to / writing
        }
        guard let window: AXUIElement = element(app, kAXFocusedWindowAttribute) else { return texts }
        if let title: String = attribute(window, kAXTitleAttribute) { texts.append(title) }

        // Breadth-first so headers and recipients (near the top of the tree) come before deep content.
        var queue: [AXUIElement] = [window]
        var visited = 0
        while !queue.isEmpty, visited < maxElements, Date() < deadline {
            let node = queue.removeFirst()
            visited += 1
            if isSecure(node) { continue }
            for key in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
                if let s: String = attribute(node, key), !s.isEmpty { texts.append(String(s.prefix(500))) }
            }
            if let children: [AXUIElement] = attribute(node, kAXChildrenAttribute) {
                queue.append(contentsOf: children)
            }
        }
        return texts
    }

    /// Chrome, Dia, Arc, Brave, Edge and Electron apps keep web-page contents out of the accessibility tree
    /// until an assistive app asks for it. This is the documented switch (the same one screen readers and
    /// Wispr Flow use); without it, WhatsApp Web's message box and names are invisible to Evoo.
    static func enableWebAccessibility(for pid: pid_t) {
        guard !enabledPIDs.contains(pid) else { return }
        enabledPIDs.insert(pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    nonisolated(unsafe) private static var enabledPIDs: Set<pid_t> = []

    /// The text field that has keyboard focus, unless it's a password field.
    static func focusedField() -> AXUIElement? {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier { enableWebAccessibility(for: pid) }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        guard let field = element(system, kAXFocusedUIElementAttribute), !isSecure(field) else { return nil }
        return field
    }

    static func value(of field: AXUIElement) -> String? {
        attribute(field, kAXValueAttribute)
    }

    private static func isSecure(_ el: AXUIElement) -> Bool {
        (attribute(el, kAXSubroleAttribute) as String?) == kAXSecureTextFieldSubrole
    }

    private static func attribute<T>(_ el: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
