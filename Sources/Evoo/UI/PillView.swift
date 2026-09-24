import EvooCore
import SwiftUI

/// The always-on dictation pill.
///  idle      → a slim bar; hover to reveal language + mic controls and the Fn hint
///  recording → live waveform with cancel / finish
///  working   → animated dots while the local models run
struct PillView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var settings: AppSettings
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            if hovering, controller.phase == .idle {
                hint
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            pill
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .fixedSize()
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: hovering)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: controller.phase)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var pill: some View {
        Group {
            switch controller.phase {
            case .idle where hovering: expanded
            case .idle: collapsed
            case .recording: recording
            case .transcribing, .refining: working
            case let .message(text): message(text)
            }
        }
        .background(Capsule().fill(Color.black.opacity(0.88)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }

    // MARK: States

    private var collapsed: some View {
        Capsule()
            .fill(Color.white.opacity(0.35))
            .frame(width: 28, height: 3)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
    }

    private var expanded: some View {
        HStack(spacing: 4) {
            Menu {
                Picker("Language", selection: $settings.language) {
                    ForEach(DictationLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "globe")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Language: \(settings.language.title)")

            Button(action: controller.toggleFromUI) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 30)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .help("Start hands-free dictation")

            Text(settings.language == .english ? "EN" : settings.language == .hinglish ? "HI·EN" : "HI")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 6)
        }
        .padding(4)
    }

    private var recording: some View {
        HStack(spacing: 8) {
            iconButton("xmark", help: "Cancel (Esc)", action: controller.cancel)
            Waveform(levels: controller.levels)
                .frame(width: 84, height: 22)
            iconButton("checkmark", help: "Finish", tint: .white, action: controller.stop)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var working: some View {
        HStack(spacing: 6) {
            WorkingDots()
            Text(controller.phase == .refining ? "Polishing" : "Transcribing")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(2)
            .frame(maxWidth: 280)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }

    private var hint: some View {
        HStack(spacing: 4) {
            Text("Hold")
            Text("fn").fontWeight(.bold)
            Text("to dictate")
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.88)))
    }

    private func iconButton(_ symbol: String, help: String, tint: Color = .white.opacity(0.7),
                            action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct Waveform: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2.5, height: max(3, CGFloat(levels[i]) * 22))
            }
        }
        .animation(.linear(duration: 0.08), value: levels)
    }
}

private struct WorkingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0 ..< 3) { i in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 4, height: 4)
                        .opacity(0.35 + 0.65 * max(0, sin(t * 6 - Double(i) * 0.7)))
                }
            }
        }
    }
}
