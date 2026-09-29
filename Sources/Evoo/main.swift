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

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu-bar app: no Dock icon
app.run()
