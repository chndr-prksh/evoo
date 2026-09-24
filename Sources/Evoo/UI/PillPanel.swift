import AppKit
import Combine
import SwiftUI

/// Borderless, non-activating panel that floats above every app at the bottom-center of the screen.
/// Non-activating matters: clicking the pill must never steal focus from the app you're dictating into.
final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private var hosting: NSHostingView<PillView>!
    private var sizeObserver: AnyCancellable?

    init(controller: DictationController) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false

        hosting = NSHostingView(rootView: PillView(controller: controller, settings: controller.settings))
        hosting.sizingOptions = [.intrinsicContentSize]
        contentView = hosting

        // Keep the panel exactly the size of the pill so it never blocks clicks around it.
        sizeObserver = hosting.publisher(for: \.intrinsicContentSize)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reposition() }
        NotificationCenter.default.addObserver(self, selector: #selector(reposition),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        reposition()
    }

    @objc func reposition() {
        let size = hosting.fittingSize
        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        let origin = NSPoint(x: area.midX - size.width / 2, y: area.minY + 10)
        setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
