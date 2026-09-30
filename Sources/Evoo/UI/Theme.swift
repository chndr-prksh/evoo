import AppKit
import SwiftUI

/// The website's look for Evoo's windows: white, near-black ink, soft grey cards with hairline borders, black
/// primary buttons — no system blue. Windows stay light even in dark mode (the pill stays dark on purpose).
enum Theme {
    static let ink = Color(red: 0.059, green: 0.067, blue: 0.082)      // #0f1115
    static let ink2 = Color(red: 0.27, green: 0.29, blue: 0.34)        // #454b57
    static let muted = Color(red: 0.42, green: 0.45, blue: 0.50)       // #6b7280
    static let soft = Color(red: 0.965, green: 0.969, blue: 0.976)     // #f6f7f9
    static let line = Color(red: 0.906, green: 0.910, blue: 0.925)     // #e7e8ec
    static let green = Color(red: 0.075, green: 0.639, blue: 0.357)    // #13a35b
    static let greenSoft = Color(red: 0.914, green: 0.973, blue: 0.941)

    /// Light, white windows regardless of the system appearance.
    @MainActor static func style(_ window: NSWindow) {
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
    }
}

/// A card like the website's: soft fill, hairline border.
struct CardBackground: ViewModifier {
    var radius: CGFloat = 12
    func body(content: Content) -> some View {
        content.background(RoundedRectangle(cornerRadius: radius).fill(Theme.soft))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.line))
    }
}

extension View {
    func card(radius: CGFloat = 12) -> some View { modifier(CardBackground(radius: radius)) }
    /// Window-wide: black accents instead of blue, white background.
    func evooLook() -> some View { tint(Theme.ink).accentColor(Theme.ink).background(Color.white) }
}
