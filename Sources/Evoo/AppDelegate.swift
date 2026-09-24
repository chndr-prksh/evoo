import AppKit
import Combine
import EvooCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = DictationController()
    private var statusItem: NSStatusItem!
    private var pill: PillPanel!
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Evoo")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        pill = PillPanel(controller: controller)
        controller.settings.$showPill
            .sink { [weak self] show in show ? self?.pill.orderFrontRegardless() : self?.pill.orderOut(nil) }
            .store(in: &cancellables)
        controller.$phase
            .sink { [weak self] phase in
                self?.statusItem.button?.image = NSImage(
                    systemSymbolName: phase == .recording ? "waveform.circle.fill" : "waveform",
                    accessibilityDescription: "Evoo"
                )
            }
            .store(in: &cancellables)

        controller.bootstrap()
        if !controller.permissions.allGranted { openSettings() }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = controller.settings

        let status = controller.modelStatus ?? (controller.permissions.allGranted
            ? "Ready — hold fn to dictate" : "Permissions needed")
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())

        menu.addItem(item(controller.phase == .recording ? "Stop Dictation" : "Start Hands-free Dictation",
                          #selector(toggleDictation)))
        let repaste = item("Paste Last Transcript", #selector(repaste))
        repaste.isEnabled = controller.lastText != nil
        menu.addItem(repaste)
        menu.addItem(.separator())

        let languages = NSMenu()
        for language in DictationLanguage.allCases {
            let entry = item(language.title, #selector(selectLanguage(_:)))
            entry.representedObject = language.rawValue
            entry.state = settings.language == language ? .on : .off
            languages.addItem(entry)
        }
        menu.addItem(withTitle: "Language", action: nil, keyEquivalent: "").submenu = languages

        let refine = item("Use Local AI When Needed", #selector(toggleRefinement))
        refine.state = settings.refinementEnabled ? .on : .off
        menu.addItem(refine)
        let pillItem = item("Show Floating Pill", #selector(togglePill))
        pillItem.state = settings.showPill ? .on : .off
        menu.addItem(pillItem)

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Quit Evoo", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    @objc private func toggleDictation() { controller.toggleFromUI() }
    @objc private func repaste() { controller.repasteLast() }
    @objc private func toggleRefinement() { controller.settings.refinementEnabled.toggle() }
    @objc private func togglePill() { controller.settings.showPill.toggle() }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let language = DictationLanguage(rawValue: raw) {
            controller.settings.language = language
        }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(controller: controller, settings: controller.settings,
                                    permissions: controller.permissions)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Evoo Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
