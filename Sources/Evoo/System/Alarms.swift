import AppKit
import os

/// Alarms and timers set by voice. Evoo rings them itself (a sound that repeats until you stop it, and a small
/// window with Stop and Snooze), so nothing else has to be set up. They are saved, so quitting Evoo doesn't lose
/// them; one that came due while the Mac was asleep rings when it wakes.
@MainActor
final class Alarms {
    static let shared = Alarms()

    struct Alarm: Codable, Equatable, Identifiable {
        var id = UUID()
        var label: String
        var date: Date
    }

    private(set) var pending: [Alarm] = []
    private var timer: Timer?
    private var sound: NSSound?
    private var ringing = false
    private let log = Logger(subsystem: "app.evoo", category: "alarms")
    private static let key = "alarms"
    /// An alarm missed by more than this (the Mac was off all day) is dropped instead of ringing late.
    private static let stale: TimeInterval = 6 * 3600

    func start() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Alarm].self, from: data)
        {
            pending = saved.filter { $0.date > Date().addingTimeInterval(-Self.stale) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in Alarms.shared.schedule() }
        }
        schedule()
    }

    /// What the pill says: "Alarm · 7:00 AM" or "Pasta · in 12 min".
    @discardableResult
    func add(_ label: String, at date: Date) -> String {
        pending.append(Alarm(label: label, date: date))
        save()
        schedule()
        log.notice("alarm set for \(date.formatted(date: .abbreviated, time: .shortened), privacy: .public)")
        let minutes = Int((date.timeIntervalSinceNow / 60).rounded())
        if minutes < 60 { return "\(label) · in \(max(1, minutes)) min" }
        let day = Calendar.current.isDateInToday(date) ? "" : Calendar.current.isDateInTomorrow(date) ? "tomorrow " : date.formatted(.dateTime.weekday(.wide)) + " "
        return "\(label) · \(day)\(date.formatted(date: .omitted, time: .shortened))"
    }

    /// Returns how many were cancelled.
    func cancelAll() -> Int {
        let n = pending.count
        pending = []
        save()
        schedule()
        stopSound()
        return n
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(pending), forKey: Self.key)
    }

    private func schedule() {
        timer?.invalidate()
        guard let next = pending.map(\.date).min() else { return }
        let fire = Timer(fire: max(next, Date().addingTimeInterval(0.2)), interval: 0, repeats: false) { _ in
            Task { @MainActor in Alarms.shared.ringDue() }
        }
        fire.tolerance = 0.5
        RunLoop.main.add(fire, forMode: .common)
        timer = fire
    }

    private func ringDue() {
        guard !ringing else { return } // the next one rings when this window is closed
        let now = Date()
        guard let alarm = pending.filter({ $0.date <= now }).min(by: { $0.date < $1.date }) else { return schedule() }
        pending.removeAll { $0.id == alarm.id }
        save()
        ring(alarm)
        ringDue()
        schedule()
    }

    private func ring(_ alarm: Alarm) {
        ringing = true
        log.notice("alarm ringing")
        sound = NSSound(named: "Glass") ?? NSSound(named: "Ping")
        sound?.loops = true
        sound?.play()
        // Quiet again after two minutes even if nobody is there.
        let silence = Task { try? await Task.sleep(for: .seconds(120)); self.stopSound() }
        let alert = NSAlert()
        alert.messageText = alarm.label
        alert.informativeText = "Set for \(alarm.date.formatted(date: .omitted, time: .shortened))"
        alert.addButton(withTitle: "Stop")
        alert.addButton(withTitle: "Snooze 5 min")
        alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        let answer = alert.runModal()
        silence.cancel()
        stopSound()
        ringing = false
        if answer == .alertSecondButtonReturn { add(alarm.label, at: Date().addingTimeInterval(300)) }
    }

    private func stopSound() {
        sound?.stop()
        sound = nil
    }
}
