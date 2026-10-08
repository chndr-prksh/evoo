#if DEBUG
import AppKit
import EvooCore
import SwiftUI

/// `Evoo --snapshot-pill <dir>` renders every pill state to PNGs (debug builds only),
/// so UI changes can be reviewed without granting permissions or recording audio.
@MainActor
enum PillSnapshots {
    /// Renders the welcome tour's pages too.
    static func welcome(into dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let permissions = Permissions()
        permissions.refresh()
        let controller = DictationController()
        for page in 0 ..< 5 {
            let view = WelcomeView(permissions: permissions, controller: controller, settings: controller.settings,
                                   finish: {}, page: page)
                .background(Color(nsColor: .windowBackgroundColor))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1.5
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            {
                try? png.write(to: dir.appendingPathComponent("welcome-\(page).png"))
            }
        }
    }

    static func run(into dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let controller = DictationController()
        let model = PillModel()
        let wave: [Float] = (0 ..< 18).map { i in Float(0.25 + 0.7 * abs(sin(Double(i) * 0.7))) }
        let states: [(String, DictationController.Phase, Bool)] = [
            ("1-idle", .idle, false),
            ("2-hover", .idle, true),
            ("3-recording", .recording, false),
            ("3-recording-live", .recording, false), ("3-recording-command", .recording, false),
            ("3-recording-command-empty", .recording, false),
            ("4-working", .transcribing, false),
            ("6-tip", .idle, false),
            ("7-tip-long", .idle, false),
            ("5-message", .message("Hindi/Hinglish model is still preparing (first time only) — try again shortly"), false),
            ("8-side-idle", .idle, false), ("8-side-hover", .idle, true), ("8-side-recording", .recording, false),
            ("8-side-working", .transcribing, false),
        ]
        for (name, phase, hovering) in states {
            controller.debugSet(phase: phase, levels: wave)
            model.hovering = hovering
            model.vertical = name.hasPrefix("8-side")
            controller.live.reset()
            switch name {
            case "3-recording-live":
                controller.live.show("So I wanted to give everyone a quick update on where we are with the launch")
                model.dismissTip()
            case "3-recording-command":
                controller.live.command = true
                controller.live.show("Close the tab and switch to Claude")
                model.dismissTip()
            case "3-recording-command-empty":
                controller.live.command = true
                model.dismissTip()
            case "6-tip": model.present(Tips.all[1])
            case "7-tip-long": model.present(Tips.all[4]) // longest phrase
            default: model.dismissTip()
            }
            let view = PillView(controller: controller, settings: controller.settings, model: model)
                .frame(width: 440, height: 300, alignment: .bottom)
                .background(Color(white: 0.93)) // light desktop behind, like a real wallpaper
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            {
                try? png.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
    }
}
#endif
