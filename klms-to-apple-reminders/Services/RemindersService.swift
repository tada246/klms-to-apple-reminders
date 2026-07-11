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

    /// dedup キー = 課題の数値 ID。UID（例: "event-assignment-1269269"）と
    /// リマインダーの URL（例: "…/assignments/1269269"）の両方から同じ ID を取り出せる。
    ///
    /// 以前は `submitted`（Canvas API の提出済みフラグ）で重複回避していたが、.ics には
    /// 提出済みフラグが無い。当初は notes に `[klms:<uid>]` マーカーを埋めていたが、それが
    /// ユーザーの目に見えるノイズになるため、リマインダーの url に埋まる課題 ID で照合する
    /// 方式に変更した（notes は綺麗なまま保てる）。
    private static let idRegex = try! NSRegularExpression(pattern: "assignments?[-_/](\\d+)")

    /// 純粋関数（EKEventStore 非依存）なので nonisolated。テストからも同期的に呼べる。
    nonisolated static func assignmentID(in text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = idRegex.firstMatch(in: text, range: range),
              let r = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[r])
    }

    nonisolated static func assignmentID(fromUID uid: String) -> String? {
        assignmentID(in: uid)
    }

    nonisolated static func assignmentID(from url: URL?) -> String? {
        guard let s = url?.absoluteString else { return nil }
        return assignmentID(in: s)
    }

    /// 既存リマインダーの課題 ID 集合を取得する。
    ///
    /// 完了済みリマインダーも含めて走査する（isCompleted によるフィルタは行わない）。
    /// これは、完了済みの課題が次回同期時に「未走査」扱いとなって復活してしまう
    /// のを防ぐため。ユーザーが完了にしたリマインダーは再作成されるべきではない。
    func existingAssignmentIDs(in list: EKCalendar) async -> Set<String> {
        let predicate = store.predicateForReminders(in: [list])
        return await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { reminders in
                let ids = Set((reminders ?? []).compactMap { Self.assignmentID(from: $0.url) })
                cont.resume(returning: ids)
            }
        }
    }

    func addReminder(_ assignment: Assignment, to list: EKCalendar) throws {
        let reminder = EKReminder(eventStore: store)
        reminder.title = assignment.title
        reminder.calendar = list
        reminder.url = assignment.url

        if let due = assignment.dueAt {
            // 終日課題（VALUE=DATE）は時刻を付けない → リマインダーが「0:00」を表示しない。
            let fields: Set<Calendar.Component> = assignment.isAllDay
                ? [.year, .month, .day]
                : [.year, .month, .day, .hour, .minute]
            reminder.dueDateComponents = Calendar.current.dateComponents(fields, from: due)
        }

        // notes はコース名のみ（URL はリマインダーの url フィールドにあるので重複させない）。
        reminder.notes = assignment.courseName.isEmpty ? nil : assignment.courseName

        try store.save(reminder, commit: true)
    }
}
