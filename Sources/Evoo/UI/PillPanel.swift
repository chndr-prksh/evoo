import AppKit
import Combine
import EvooCore
import SwiftUI

/// Shared between the panel (AppKit) and the pill (SwiftUI).
@MainActor
final class PillModel: ObservableObject {
    static let shared = PillModel()

    /// How long a tip stays on screen.
    static let tipSeconds: Double = 10

    /// A feature tip shown above the pill (see `Tips`); fades after 10 s unless the pointer is on it.
    @Published private(set) var tip: Tip?
    /// When the tip will fade; nil while it's paused (pointer on it).
    @Published private(set) var tipExpires: Date?
    var tipRect: CGRect = .zero
    var hoveringTip = false {
        didSet {
            guard tip != nil, hoveringTip != oldValue else { return }
            if hoveringTip {
                dismissTask?.cancel()
                tipExpires = nil
            } else {
                scheduleDismiss(after: 4)
            }
        }
    }
    private var dismissTask: Task<Void, Never>?

    func present(_ tip: Tip) {
        self.tip = tip
        scheduleDismiss(after: Self.tipSeconds)
    }

    func dismissTip() {
        dismissTask?.cancel()
        tip = nil
        tipExpires = nil
        tipRect = .zero
    }

    private func scheduleDismiss(after seconds: Double) {
        dismissTask?.cancel()
        tipExpires = Date().addingTimeInterval(seconds)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, !self.hoveringTip else { return }
            self.dismissTip()
        }
    }

    @Published var hovering = false
    /// The pill's frame in the hosting view's coordinates (top-left origin).
    var pillRect: CGRect = .zero
    var showLanguageMenu: () -> Void = {}
    var openClassNotes: () -> Void = {}

    /// Where the pill sits along the bottom of the screen: 0 = left edge, 0.5 = center, 1 = right edge.
    /// Drag the pill to move it; Settings has Left / Center / Right.
    var position: Double {
        get { UserDefaults.standard.object(forKey: "pillPosition") as? Double ?? 0.5 }
        set {
            UserDefaults.standard.set(min(1, max(0, newValue)), forKey: "pillPosition")
            reposition()
        }
    }

    /// Set by the panel: move it horizontally by `dx` points (while dragging), and remember where it ended.
    var dragBy: (CGFloat) -> Void = { _ in }
    var dragEnded: () -> Void = {}
    var reposition: () -> Void = {}
}

/// A fixed-size, transparent, non-activating panel at the bottom-center of the screen.
///
/// - Non-activating: clicking the pill never steals focus from the app you're dictating into.
/// - Click-through: the panel ignores the mouse everywhere except over the pill itself, so its
///   transparent area never blocks the Dock or windows below.
final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private static let size = NSSize(width: 440, height: 300)
    private let model = PillModel.shared
    private let controller: DictationController
    private var monitors: [Any] = []

    init(controller: DictationController) {
        self.controller = controller
        super.init(contentRect: NSRect(origin: .zero, size: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true

        let root = PillView(controller: controller, settings: controller.settings, model: model)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .bottom)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        contentView = hosting

        model.showLanguageMenu = { [weak self] in self?.popUpLanguageMenu() }
        model.dragBy = { [weak self] dx in self?.slide(by: dx) }
        model.dragEnded = { [weak self] in self?.savePosition() }
        model.reposition = { [weak self] in self?.reposition() }

        // Track the pointer ourselves: while click-through, the panel gets no hover events.
        let track: (NSEvent) -> Void = { [weak self] _ in self?.updateHover() }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: track) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .mouseExited],
                                                    handler: { track($0); return $0 })
        {
            monitors.append(m)
        }
        acceptsMouseMovedEvents = true

        NotificationCenter.default.addObserver(self, selector: #selector(reposition),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        reposition()
    }

    @objc func reposition() {
        guard let area = currentArea else { return }
        let x = area.minX + area.width * model.position - Self.size.width / 2
        setFrameOrigin(NSPoint(x: clampX(x, in: area), y: area.minY + 6))
    }

    private var currentArea: NSRect? {
        (NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? screen ?? NSScreen.main)?.visibleFrame
    }

    /// Keeps the pill (not the whole transparent panel) on screen, with a little margin.
    private func clampX(_ x: CGFloat, in area: NSRect) -> CGFloat {
        let half = Self.size.width / 2, pill: CGFloat = 90, margin: CGFloat = 8
        return min(max(x, area.minX - half + pill / 2 + margin), area.maxX - half - pill / 2 - margin)
    }

    private func slide(by dx: CGFloat) {
        guard let area = currentArea else { return }
        setFrameOrigin(NSPoint(x: clampX(frame.minX + dx, in: area), y: frame.minY))
    }

    private func savePosition() {
        guard let area = currentArea, area.width > 0 else { return }
        UserDefaults.standard.set(Double((frame.midX - area.minX) / area.width), forKey: "pillPosition")
    }

    private func updateHover() {
        // Convert SwiftUI (top-left) rects to screen coordinates, with a little slack around them.
        func onScreen(_ r: CGRect) -> Bool {
            r != .zero && NSRect(x: frame.minX + r.minX, y: frame.maxY - r.maxY, width: r.width, height: r.height)
                .insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation)
        }
        let overPill = onScreen(model.pillRect)
        let overTip = model.tip != nil && onScreen(model.tipRect)
        let interactive = overPill || overTip
        if ignoresMouseEvents == interactive { ignoresMouseEvents = !interactive }
        if model.hovering != overPill { model.hovering = overPill }
        if model.hoveringTip != overTip { model.hoveringTip = overTip }
    }

    private func popUpLanguageMenu() {
        let menu = NSMenu()
        for language in DictationLanguage.allCases {
            let item = NSMenuItem(title: language.title, action: #selector(pickLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = controller.settings.language == language ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func pickLanguage(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let language = DictationLanguage(rawValue: raw) {
            controller.settings.language = language
        }
    }

    deinit {
        monitors.forEach(NSEvent.removeMonitor)
    }
}
