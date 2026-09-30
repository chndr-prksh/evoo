import AppKit
import SwiftUI

/// First-run tour: why Evoo is trustworthy, what it can do, and the permissions it needs — step by step.
/// Skippable at any point; reopen it from the menu (Welcome Tour…).
struct WelcomeView: View {
    @ObservedObject var permissions: Permissions
    @ObservedObject var controller: DictationController
    @ObservedObject var settings: AppSettings
    let finish: () -> Void

    @State var page = 0
    @State private var tryText = ""
    @State private var drag: CGFloat = 0
    @FocusState private var tryFocused: Bool
    @State private var wantAI = true
    @State private var wantPolish = true
    @State private var wantLogin = true
    @State private var wantFast = false
    @State private var applied = false
    private let pages = 5
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < pages - 1 {
                    Button("Skip", action: finish).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding([.top, .horizontal], 18)
            .frame(height: 36)

            Group {
                switch page {
                case 0: trust
                case 1: features
                case 2: setup
                case 3: configure
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36)
            .offset(x: drag)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 30)
                .onChanged { drag = $0.translation.width / 3 }
                .onEnded { value in
                    withAnimation(.spring(response: 0.35)) {
                        if value.translation.width < -60 { go(page + 1) }
                        if value.translation.width > 60 { go(page - 1) }
                        drag = 0
                    }
                })
            .id(page)
            .transition(.opacity)

            HStack {
                Button("Back") { withAnimation { go(page - 1) } }
                    .opacity(page == 0 ? 0 : 1)
                Spacer()
                HStack(spacing: 7) {
                    ForEach(0 ..< pages, id: \.self) { i in
                        Circle().fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                            .onTapGesture { withAnimation { go(i) } }
                    }
                }
                Spacer()
                Button(page == pages - 1 ? "Start using Evoo" : page == 3 && !applied ? "Set up & continue" : "Next") {
                    if page == 3, !applied { applyRecommended() }
                    if page == pages - 1 { finish() } else { withAnimation { go(page + 1) } }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 640, height: 560)
        .onKeyPress(.rightArrow) { withAnimation { go(page + 1) }; return .handled }
        .onKeyPress(.leftArrow) { withAnimation { go(page - 1) }; return .handled }
        .onReceive(refresh) { _ in if page == 2 { permissions.refresh() } }
        .onChange(of: wantAI) { _, on in if !on { wantPolish = false } }
    }

    private func go(_ p: Int) { page = min(max(p, 0), pages - 1) }

    // MARK: - Pages

    private var trust: some View {
        VStack(spacing: 22) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56)).foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text("Welcome to Evoo").font(.system(size: 28, weight: .bold))
                Text("Hold fn, speak, release — clean text wherever your cursor is.")
                    .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                Trust(icon: "lock.shield.fill", color: .green, title: "Your voice never leaves this Mac",
                      detail: "Speech is turned into text right here. Nothing is uploaded, ever.")
                Trust(icon: "wifi.slash", color: .blue, title: "Works offline",
                      detail: "No internet needed after the one-time model download — on a plane, anywhere.")
                Trust(icon: "cpu.fill", color: .purple, title: "Runs on your Mac's own chip",
                      detail: "Apple's Neural Engine does the work: fast, and nothing to pay for.")
                Trust(icon: "person.crop.circle.badge.xmark", color: .orange, title: "No account, no tracking",
                      detail: "No sign-up, no analytics. Your history and learned words stay on this Mac.")
                Trust(icon: "chevron.left.forwardslash.chevron.right", color: .gray, title: "Free and open source",
                      detail: "Anyone can read the code on GitHub and check all of the above.")
            }
        }
    }

    private var features: some View {
        VStack(spacing: 18) {
            Text("What you can do").font(.system(size: 26, weight: .bold))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                Feature(icon: "text.cursor", title: "Dictate anywhere", example: "Any app, any text box")
                Feature(icon: "arrow.uturn.backward", title: "Change your mind", example: "“tomorrow, no, Friday” → Friday")
                Feature(icon: "list.bullet", title: "Lists & formatting", example: "“buy milk, eggs and bread”")
                Feature(icon: "app.badge", title: "Open & search apps", example: "“open Slack”, “search Google for…”")
                Feature(icon: "command", title: "Control your Mac", example: "“new tab”, “volume 30”, “click Send”")
                Feature(icon: "bell", title: "Reminders & notes", example: "“remind me to call Divya at 5”")
                Feature(icon: "pencil.line", title: "Edit by voice", example: "“replace Tuesday with Wednesday”")
                Feature(icon: "brain", title: "Learns your words", example: "Fix a name once — Evoo remembers")
            }
            Text("New to all this? Evoo shows a small tip now and then, one feature at a time.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set up in four steps").font(.system(size: 26, weight: .bold))
            Text("macOS asks you to approve each one. Click the button, then switch Evoo on in the window that opens — this page updates by itself.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Step(number: 1, icon: "mic.fill", title: "Microphone", why: "So Evoo can hear you.",
                 how: "Click Allow when macOS asks.", done: permissions.granted[.microphone] == true) {
                permissions.request(.microphone)
            }
            Step(number: 2, icon: "keyboard", title: "Input Monitoring", why: "So Evoo notices when you hold fn.",
                 how: "In System Settings, switch on Evoo.", done: permissions.granted[.inputMonitoring] == true) {
                permissions.request(.inputMonitoring)
            }
            Step(number: 3, icon: "accessibility", title: "Accessibility", why: "So Evoo can type into the app you're using.",
                 how: "In System Settings, switch on Evoo.", done: permissions.granted[.accessibility] == true) {
                permissions.request(.accessibility)
            }
            Step(number: 4, icon: "globe", title: "Free up the fn key",
                 why: "So macOS doesn't also open emoji or dictation.",
                 how: "Keyboard › “Press 🌐 key to” → Do Nothing.", done: nil) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
            }
        }
    }

    /// One screen for everything that used to mean a trip to Settings: the AI model download and the switches.
    private var configure: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set up Evoo").font(.system(size: 26, weight: .bold))
            Text("We've picked the best settings. Click Set up & continue — downloads run in the background, and you can change anything later in Settings.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            SetupRow(icon: "bolt.fill", title: "Extra-fast speech model",
                     detail: controller.modelStatus
                         ?? "Off is recommended: the standard model hears short commands and names better, and long dictations are transcribed while you speak either way.",
                     state: controller.modelStatus != nil ? .working : applied ? .done : .off, isOn: $wantFast, locked: false)
            SetupRow(icon: "sparkles", title: SystemInfo.isLowMemory ? "Local AI models (3.1 GB, once)" : "Local AI model (Qwen3 4B · 2.5 GB, once)",
                     detail: "Powers class notes, rewrite by voice (“make this more formal”), replies and translation.",
                     state: aiState, isOn: $wantAI, locked: false, progress: controller.refinerDownloadProgress)
            SetupRow(icon: "wand.and.stars", title: "Polish every dictation with AI",
                     detail: SystemInfo.isLowMemory
                         ? "Fixes grammar and messy phrasing — sentence by sentence while you speak, so long dictations are ready about a second after you let go."
                         : "Fixes grammar and messy phrasing after Evoo's rules — while you speak, so it's ready about a second after you let go.",
                     state: settings.smartCleanup ? .done : .off, isOn: $wantPolish, locked: false)
                .disabled(!wantAI)
            SetupRow(icon: "brain", title: "Learn names and words",
                     detail: "From your screen and your corrections — kept only on this Mac.",
                     state: applied ? .done : .off, isOn: .constant(true), locked: true)
            SetupRow(icon: "power", title: "Start Evoo when you log in",
                     detail: "So fn dictation is always there.",
                     state: LoginItem.isEnabled ? .done : .off, isOn: $wantLogin, locked: false)
        }
    }

    private var aiState: SetupRow.State {
        if controller.refinerDownloadProgress != nil { return .working }
        return controller.notesModelInstalled && controller.refinerInstalled ? .done : .off
    }

    /// Turns on the recommended switches and starts the AI download (continues after the tour closes).
    private func applyRecommended() {
        applied = true
        settings.fastestModel = wantFast
        settings.formatText = true
        settings.useScreenContext = true
        settings.learnFromScreen = true
        settings.learnFromEdits = true
        settings.appCommands = true
        settings.keepHistory = true
        settings.showTips = true
        settings.refinerModel = SystemInfo.isLowMemory ? .qwen3_0_6b : DictationController.notesModel
        if wantLogin, !LoginItem.isEnabled { try? LoginItem.set(true) }
        if wantAI {
            if controller.refinerInstalled {
                settings.smartCleanup = wantPolish
                controller.prepareRefiner()
                if !controller.notesModelInstalled { controller.downloadNotesModel() }
            } else {
                controller.downloadRefiner(enableCleanup: wantPolish, thenNotesModel: true)
            }
        }
    }

    private var ready: some View {
        VStack(spacing: 18) {
            Image(systemName: permissions.allGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(permissions.allGranted ? .green : .orange)
            Text(permissions.allGranted ? "You're all set" : "Almost there").font(.system(size: 26, weight: .bold))
            Text(permissions.allGranted
                ? "Hold fn and say something. Release fn to see it typed below."
                : "Some permissions are still off — go back a page, or finish later in Settings.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            TextEditor(text: $tryText)
                .focused($tryFocused)
                .onAppear { tryFocused = true } // ready to dictate into, no click needed
                .font(.body)
                .frame(height: 110)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.3)))
            Text("Try: “Let's meet tomorrow, no, day after tomorrow.”")
                .font(.callout).foregroundStyle(.secondary)
            if let p = controller.refinerDownloadProgress {
                ProgressView(value: p) {
                    Text("Downloading the local AI model… \(Int(p * 100))% — dictation already works; you can close this window.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SetupRow: View {
    enum State { case off, working, done }
    let icon: String
    let title: String
    let detail: String
    let state: State
    @Binding var isOn: Bool
    let locked: Bool
    var progress: Double?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(.tint).frame(width: 26).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let progress {
                    ProgressView(value: progress).frame(maxWidth: 260)
                    Text("Downloading \(Int(progress * 100))%").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            switch state {
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 18))
            case .working: ProgressView().controlSize(.small)
            case .off:
                if locked { Image(systemName: "checkmark.circle").foregroundStyle(.secondary) } else {
                    Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }
}

private struct Trust: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct Feature: View {
    let icon: String
    let title: String
    let example: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(example).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
    }
}

private struct Step: View {
    let number: Int
    let icon: String
    let title: String
    let why: String
    let how: String
    /// nil = can't be checked automatically (the fn key setting).
    let done: Bool?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(done == true ? Color.green : Color.accentColor.opacity(0.15))
                if done == true {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 13, weight: .bold)).foregroundStyle(.tint)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: icon).font(.headline)
                Text("\(why) \(how)").font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if done == true {
                Text("Done").foregroundStyle(.green).font(.callout.weight(.semibold))
            } else {
                Button(done == nil ? "Open Settings" : "Grant…", action: action)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }
}
