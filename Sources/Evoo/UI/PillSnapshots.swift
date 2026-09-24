#if DEBUG
import AppKit
import SwiftUI

/// `Evoo --snapshot-pill <dir>` renders every pill state to PNGs (debug builds only),
/// so UI changes can be reviewed without granting permissions or recording audio.
@MainActor
enum PillSnapshots {
    static func run(into dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let controller = DictationController()
        let model = PillModel()
        let wave: [Float] = (0 ..< 18).map { i in Float(0.25 + 0.7 * abs(sin(Double(i) * 0.7))) }
        let states: [(String, DictationController.Phase, Bool)] = [
            ("1-idle", .idle, false),
            ("2-hover", .idle, true),
            ("3-recording", .recording, false),
            ("4-working", .transcribing, false),
            ("5-message", .message("Hindi/Hinglish model is still preparing (first time only) — try again shortly"), false),
        ]
        for (name, phase, hovering) in states {
            controller.debugSet(phase: phase, levels: wave)
            model.hovering = hovering
            let view = PillView(controller: controller, settings: controller.settings, model: model)
                .frame(width: 360, height: 96, alignment: .bottom)
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
