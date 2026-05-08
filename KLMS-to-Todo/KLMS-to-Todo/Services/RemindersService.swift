import EventKit
import Foundation

enum RemindersError: Error, LocalizedError {
    case accessDenied
    case listNotFound

    var errorDescription: String? {
        switch self {
        case .accessDenied:  return "リマインダーへのアクセスが拒否されています。システム環境設定で許可してください。"
        case .listNotFound:  return "リマインダーリストが見つかりません。"
        }
    }
}

@MainActor
class RemindersService {
    private let store = EKEventStore()

    func requestAccess() async throws {
        if #available(macOS 14.0, *) {
            guard try await store.requestFullAccessToReminders() else {
                throw RemindersError.accessDenied
            }
        } else {
            let granted = await withCheckedContinuation { cont in
                store.requestAccess(to: .reminder) { ok, _ in cont.resume(returning: ok) }
            }
            if !granted { throw RemindersError.accessDenied }
        }
    }

    func findOrCreateList(named name: String) throws -> EKCalendar {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == name }) {
            return existing
        }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = name
        list.source = store.defaultCalendarForNewReminders()?.source
        try store.saveCalendar(list, commit: true)
        return list
    }

    func existingTitles(in list: EKCalendar) async -> Set<String> {
        let predicate = store.predicateForReminders(in: [list])
        return await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { reminders in
                let titles = Set((reminders ?? []).compactMap { $0.isCompleted ? nil : $0.title })
                cont.resume(returning: titles)
            }
        }
    }

    func addReminder(_ assignment: Assignment, to list: EKCalendar) throws {
        let reminder = EKReminder(eventStore: store)
        reminder.title = assignment.title
        reminder.calendar = list

        if let due = assignment.dueAt {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: due)
            reminder.dueDateComponents = comps
        }

        var notes = assignment.courseName
        if let url = assignment.url {
            notes += "\n\(url.absoluteString)"
        }
        reminder.notes = notes.isEmpty ? nil : notes

        try store.save(reminder, commit: true)
    }
}
