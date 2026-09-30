import AppKit

#if DEBUG
if let i = CommandLine.arguments.firstIndex(of: "--snapshot-pill"), i + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated {
        let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
        PillSnapshots.run(into: dir)
        PillSnapshots.welcome(into: dir)
    }
    exit(0)
}
#endif

#if DEBUG
if let i = CommandLine.arguments.firstIndex(of: "--snapshot-editor"), i + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated { EditorSnapshot.run(out: URL(fileURLWithPath: CommandLine.arguments[i + 1])) }
    NSApplication.shared.run()
}
if let i = CommandLine.arguments.firstIndex(of: "--snapshot-notes"), i + 1 < CommandLine.arguments.count {
    let app = NSApplication.shared
    MainActor.assumeIsolated {
        NotesSnapshot.current = NotesSnapshot(out: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    }
    app.run()
}
#endif

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
// In the Dock with a main window (default), or menu bar only (Settings › Show Evoo in the Dock).
app.setActivationPolicy(UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true ? .regular : .accessory)
app.run()
