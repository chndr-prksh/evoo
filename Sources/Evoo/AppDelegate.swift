import AppKit
import Combine
import EvooCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = DictationController()
    private let updater = Updater()
    private var statusItem: NSStatusItem!
    private var pill: PillPanel!
    private var settingsWindow: NSWindow?
    private var mainWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var classWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_: Notification) {
        // Get the microphone path ready now so the first fn press is instant (the mic itself stays off).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [controller] in
            controller.warmUp()
            controller.cleanScreenLearned()
            PersonalModel.shared.schedule(controller: controller)
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { [controller] _ in
            MainActor.assumeIsolated { controller.warmUp() }
        }
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

        controller.onOpenHistory = { [weak self] in self?.openHistory() }
        controller.onOpenClassNotes = { [weak self] query in self?.openClassNotes(query: query) }
        PillModel.shared.openClassNotes = { [weak self] in self?.openClassNotes(query: nil) }
        ClassNotesModel.shared.makeRecorder = { [weak self] session in
            self?.controller.makeClassRecorder(session: session)
        }
        ClassNotesModel.shared.microphone = { AppSettings.shared.microphoneUID }
        ClassNotesModel.shared.ai = { [weak self] in self?.controller.classAI() }
        controller.bootstrap()
        updater.start()
        updater.$state
            .sink { [weak self] state in
                // A small dot next to the menu bar icon when an update is waiting.
                let waiting = if case .available = state { true } else { false }
                self?.statusItem.button?.title = waiting ? "•" : ""
            }
            .store(in: &cancellables)
        #if DEBUG
        DistributedNotificationCenter.default().addObserver(forName: .init("app.evoo.debug.dictate"), object: nil,
                                                            queue: .main) { [weak self] note in
            guard let text = note.object as? String else { return }
            MainActor.assumeIsolated { self?.controller.debugDictate(text) }
        }
        // Debug: start/stop recording as if fn were pressed (for timing the start).
        DistributedNotificationCenter.default().addObserver(forName: .init("app.evoo.debug.toggle"), object: nil,
                                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.controller.debugDryRun = true
                self?.controller.toggleFromUI()
            }
        }
        // Debug: start/stop a real dictation (full pipeline) that logs its text instead of pasting it.
        DistributedNotificationCenter.default().addObserver(forName: .init("app.evoo.debug.toggleFull"), object: nil,
                                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.controller.debugDryRun = false
                self?.controller.debugNoPaste = true
                self?.controller.toggleFromUI()
            }
        }
        // Debug: run the whole personal-model flow on a pairs file (object = path), with a short training.
        DistributedNotificationCenter.default().addObserver(forName: .init("app.evoo.debug.train"), object: nil,
                                                            queue: .main) { [weak self] note in
            guard let path = note.object as? String else { return }
            MainActor.assumeIsolated {
                guard let self, let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                      let pairs = try? JSONDecoder().decode([StylePair].self, from: data) else { return }
                Task { await PersonalModel.shared.train(controller: self.controller, pairs: pairs, iters: 5) }
            }
        }
        // Debug: open the welcome tour on its last (try-it) page.
        DistributedNotificationCenter.default().addObserver(forName: .init("app.evoo.debug.welcomeTry"), object: nil,
                                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.openWelcome(page: 4) }
        }
        #endif
        seedLifetimeTotals()
        if !UserDefaults.standard.bool(forKey: "onboarded") {
            openWelcome(page: 0)
        } else if !controller.permissions.allGranted {
            openSettings()
        }
    }

    // MARK: - Main window & Dock

    /// Clicking Evoo's Dock icon opens the main window.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        openMain()
        return true
    }

    @objc private func openMainFromMenu() { openMain() }

    func openMain() {
        if mainWindow == nil {
            let view = MainWindowView(controller: controller, settings: controller.settings,
                                      openClassNotes: { [weak self] in self?.openClassNotes(query: nil) })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Evoo"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 980, height: 680))
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("EvooMain")
            window.center()
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    /// "Show Evoo in the Dock" (Settings): Dock icon + app menu, or menu bar only.
    static func applyDockSetting(_ show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }

    /// Home's totals start from the dictations already in history (before the counters existed).
    private func seedLifetimeTotals() {
        let s = controller.settings
        guard s.wordsDictated == 0, !DictationHistory.shared.entries.isEmpty else { return }
        let words = DictationHistory.shared.entries.map { $0.text.split(whereSeparator: \.isWhitespace).count }.reduce(0, +)
        s.wordsDictated = words
        s.secondsDictated = Double(words) / 150 * 60 // ~150 words a minute spoken
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = controller.settings

        let status = controller.modelStatus ?? (controller.permissions.allGranted
            ? "Ready — hold fn to dictate" : "Permissions needed")
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(item("Open Evoo", #selector(openMainFromMenu), key: "o"))
        menu.addItem(.separator())

        menu.addItem(item(controller.phase == .recording ? "Stop Dictation" : "Start Hands-free Dictation",
                          #selector(toggleDictation)))
        let repaste = item("Paste Last Transcript", #selector(repaste))
        repaste.isEnabled = controller.lastText != nil
        menu.addItem(repaste)
        menu.addItem(.separator())

        if Features.multilingual {
            let languages = NSMenu()
            for language in Features.languages {
                let entry = item(language.title, #selector(selectLanguage(_:)))
                entry.representedObject = language.rawValue
                entry.state = settings.language == language ? .on : .off
                languages.addItem(entry)
            }
            menu.addItem(withTitle: "Language", action: nil, keyEquivalent: "").submenu = languages

            let refine = item("Use Local AI When Needed", #selector(toggleRefinement))
            refine.state = settings.refinementEnabled ? .on : .off
            menu.addItem(refine)
        }
        let pillItem = item("Show Floating Pill", #selector(togglePill))
        pillItem.state = settings.showPill ? .on : .off
        menu.addItem(pillItem)

        menu.addItem(.separator())
        menu.addItem(item("Class Notes…", #selector(openClassNotesFromMenu)))
        menu.addItem(item("History & Notes…", #selector(openHistory), key: "y"))
        menu.addItem(item("Transcribe a File…", #selector(transcribeFile)))
        addUpdateItems(to: menu)
        menu.addItem(item("Welcome Tour…", #selector(showWelcomeTour)))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Quit Evoo", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    private func addUpdateItems(to menu: NSMenu) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        guard updater.isEnabled else {
            menu.addItem(withTitle: "Evoo \(version) (local build)", action: nil, keyEquivalent: "").isEnabled = false
            menu.addItem(.separator())
            return
        }
        switch updater.state {
        case let .available(build):
            menu.addItem(item("Install Update (build \(build))…", #selector(installUpdate)))
        case let .installing(message):
            menu.addItem(withTitle: message, action: nil, keyEquivalent: "").isEnabled = false
        case .checking:
            menu.addItem(withTitle: "Checking for updates…", action: nil, keyEquivalent: "").isEnabled = false
        case let .failed(message):
            menu.addItem(withTitle: message, action: nil, keyEquivalent: "").isEnabled = false
            menu.addItem(item("Check for Updates", #selector(checkForUpdates)))
        case .idle, .upToDate:
            menu.addItem(item("Check for Updates", #selector(checkForUpdates)))
        }
        menu.addItem(withTitle: "Evoo \(version)", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
    }

    @objc private func transcribeFile() { controller.transcribeFile() }

    @objc private func openClassNotesFromMenu() { openClassNotes(query: nil) }

    func openClassNotes(query: String?) {
        if let query {
            ClassNotesModel.shared.query = query
        }
        if classWindow == nil {
            let view = ClassNotesView(model: .shared, store: .shared, controller: controller)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Class Notes"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 1100, height: 700))
            window.center()
            classWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        classWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showWelcomeTour() { openWelcome(page: 0) }

    func openWelcome(page: Int = 0) {
        if welcomeWindow == nil || page != 0 {
            welcomeWindow?.close()
            let view = WelcomeView(permissions: controller.permissions, controller: controller, settings: controller.settings, finish: { [weak self] in
                UserDefaults.standard.set(true, forKey: "onboarded")
                self?.welcomeWindow?.close()
                self?.controller.startHotkeysIfPossible()
            }, page: page)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Welcome to Evoo"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()
            welcomeWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openHistory() {
        if historyWindow == nil {
            let view = HistoryView(history: .shared, notes: .notes, query: .shared)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Evoo History"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            historyWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func checkForUpdates() { updater.check() }
    @objc private func installUpdate() { updater.install() }

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
