import AVFoundation
import EventKit
import EvooCore

/// Reminders and calendar events by voice (Apple's EventKit — macOS asks for permission the first time),
/// and reading text aloud with the Mac's built-in voices.
@MainActor
enum Assistant {
    private static let store = EKEventStore()
    private static let speaker = AVSpeechSynthesizer()

    static func addReminder(_ task: String, due: Date?) async -> String {
        guard (try? await store.requestFullAccessToReminders()) == true else {
            return "Allow Evoo to use Reminders in System Settings › Privacy & Security"
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = task
        reminder.calendar = store.defaultCalendarForNewReminders()
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        do {
            try store.save(reminder, commit: true)
            return "Reminder: \(task)" + (due.map { " · " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "")
        } catch {
            return "Couldn't save the reminder"
        }
    }

    static func addEvent(_ title: String, start: Date, minutes: Int) async -> String {
        guard (try? await store.requestFullAccessToEvents()) == true else {
            return "Allow Evoo to use Calendar in System Settings › Privacy & Security"
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(minutes * 60))
        event.calendar = store.defaultCalendarForNewEvents
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return "\(title) · \(start.formatted(date: .abbreviated, time: .shortened))"
        } catch {
            return "Couldn't add the event"
        }
    }

    /// Reads text aloud with the system voice (fully on-device).
    static func read(_ text: String) {
        speaker.stopSpeaking(at: .immediate)
        speaker.speak(AVSpeechUtterance(string: text))
    }

    static func stopReading() {
        speaker.stopSpeaking(at: .immediate)
    }
}
