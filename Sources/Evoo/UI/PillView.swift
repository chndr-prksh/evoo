import EvooCore
import SwiftUI

/// The always-on dictation pill: one capsule that morphs between states.
///   idle       slim bar
///   hover      language · mic · language badge, with a "Hold fn" hint above
///   recording  cancel · live waveform · finish
///   working    animated dots
struct PillView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: PillModel

    private enum Look: Hashable {
        case idle, hover, recording, working, message(String)
    }

    private var look: Look {
        switch controller.phase {
        case .idle: model.hovering ? .hover : .idle
        case .recording: .recording
        case .transcribing, .refining: .working
        case let .message(text): .message(text)
        }
    }

    private var size: CGSize {
        switch look {
        case .idle: CGSize(width: 40, height: 8)
        case .hover: CGSize(width: Features.multilingual ? 124 : 56, height: 34)
        case .recording: CGSize(width: 176, height: 38)
        case .working: CGSize(width: 64, height: 34)
        case .message: CGSize(width: 320, height: 46)
        }
    }

    private let spring = Animation.spring(response: 0.32, dampingFraction: 0.82)

    var body: some View {
        VStack(spacing: 8) {
            if let tip = model.tip, look != .recording {
                TipBanner(tip: tip, dismiss: model.dismissTip)
                    .background(GeometryReader { proxy in
                        Color.clear
                            .onAppear { model.tipRect = proxy.frame(in: .global) }
                            .onChange(of: proxy.frame(in: .global)) { _, rect in model.tipRect = rect }
                    })
                    .transition(.opacity.combined(with: .offset(y: 6)))
            } else if look == .hover {
                Hint(mode: settings.activationMode)
                    .transition(.opacity.combined(with: .offset(y: 4)))
            }
            capsule
        }
        .padding(.bottom, 4)
        .animation(spring, value: look)
        .animation(spring, value: model.tip)
    }

    private var capsule: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(.black.opacity(look == .idle ? 0.55 : 0.9))
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(look == .idle ? 0.35 : 0.16), lineWidth: 1)
            content
                .transition(.opacity)
                .id(look) // cross-fade content when the state changes
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: .black.opacity(look == .idle ? 0 : 0.3), radius: 8, y: 3)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { model.pillRect = proxy.frame(in: .global) }
                .onChange(of: proxy.frame(in: .global)) { _, rect in model.pillRect = rect }
        })
    }

    @ViewBuilder private var content: some View {
        switch look {
        case .idle:
            EmptyView()
        case .hover:
            HStack(spacing: 2) {
                if Features.multilingual {
                    RoundButton(symbol: "globe", help: "Language: \(settings.language.title)",
                                action: model.showLanguageMenu)
                }
                Button(action: controller.toggleFromUI) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 40, height: 26)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
                .help("Start hands-free dictation")
                if Features.multilingual {
                    Text(settings.language.badge)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 34)
                }
            }
        case .recording:
            HStack(spacing: 6) {
                RoundButton(symbol: "xmark", help: "Cancel (esc)", action: controller.cancel)
                RecordingDot()
                Waveform(levels: controller.levels)
                    .frame(width: 80, height: 28)
                RoundButton(symbol: "checkmark", help: "Finish", filled: true, action: controller.stop)
            }
        case .working:
            WorkingDots()
        case let .message(text):
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }
}

/// "Did you know" card above the pill: what the feature does, the words to say, and a close button.
private struct TipBanner: View {
    let tip: Tip
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.yellow)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(tip.text)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.white)
                if !tip.example.isEmpty {
                    Text("Say “\(tip.example)”")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
    }
}

private struct Hint: View {
    let mode: ActivationMode

    var body: some View {
        HStack(spacing: 4) {
            switch mode {
            case .toggle:
                Text("Double-tap"); Key(); Text("to dictate")
            default:
                Text("Hold"); Key(); Text("to dictate")
            }
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule(style: .continuous).fill(.black.opacity(0.9)))
        .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 1))
    }

    private struct Key: View {
        var body: some View {
            Text("fn")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.2)))
        }
    }
}

private struct RoundButton: View {
    let symbol: String
    let help: String
    var filled = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(filled ? .black : .white.opacity(hovering ? 1 : 0.75))
                .frame(width: 26, height: 26)
                .background(Circle().fill(filled ? .white : .white.opacity(hovering ? 0.22 : 0.1)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct Waveform: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(.white)
                    .frame(width: 2.5, height: max(3, CGFloat(levels[i]) * 28))
            }
        }
        .animation(.linear(duration: 0.08), value: levels)
    }
}

/// Pulsing red dot: unmistakable "recording" signal.
private struct RecordingDot: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
                .opacity(0.55 + 0.45 * (0.5 + 0.5 * sin(t * 5)))
        }
    }
}

private struct WorkingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0 ..< 3) { i in
                    Circle()
                        .fill(.white)
                        .frame(width: 5, height: 5)
                        .opacity(0.3 + 0.7 * max(0, sin(t * 7 - Double(i) * 0.8)))
                }
            }
        }
    }
}

extension DictationLanguage {
    var badge: String {
        switch self {
        case .english: "EN"
        case .hinglish: "HI·EN"
        case .hindi: "HI"
        }
    }
}
