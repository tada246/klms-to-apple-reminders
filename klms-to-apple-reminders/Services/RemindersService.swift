import EventKit
import Foundation

enum RemindersError: Error, LocalizedError {
    case accessDenied
    case listNotFound
    case fetchFailed
    case reminderNotFound

    var errorDescription: String? {
        switch self {
        case .accessDenied:     return "リマインダーへのアクセスが拒否されています。システム環境設定で許可してください。"
        case .listNotFound:     return "リマインダーリストが見つかりません。"
        case .fetchFailed:      return "リマインダーの読み込みに失敗しました。時間をおいて再試行してください。"
        case .reminderNotFound: return "更新対象のリマインダーが見つかりません。"
        }
    }
}

/// `RemindersService.apply` の結果。
struct ApplyOutcome {
    var added = 0
    var updated = 0
    /// 追加・更新に失敗した課題 ID（スナップショットを前回の値に戻すのに使う）。
    var failedIDs: Set<String> = []
    var failureMessages: [String] = []
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
    private nonisolated static let idRegex = try! NSRegularExpression(pattern: "assignments?[-_/](\\d+)")

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

    // MARK: - 読み取り

    /// リストの全リマインダー（**完了済みを含む**）を、課題 ID を持つものだけ値型にして返す。
    ///
    /// 完了済みも走査するのは、完了済みの課題が次回同期時に「未登録」扱いとなって復活してしまう
    /// のを防ぐため。ユーザーが完了にしたリマインダーは再作成されるべきではない。
    /// 読み込み自体に失敗したら nil（空配列と区別する。空と誤認すると全課題を二重追加してしまう）。
    func fetchRecords(in list: EKCalendar) async -> [ReminderRecord]? {
        let predicate = store.predicateForReminders(in: [list])
        return await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { reminders in
                cont.resume(returning: reminders?.compactMap { Self.record(from: $0) })
            }
        }
    }

    nonisolated static func record(from reminder: EKReminder) -> ReminderRecord? {
        guard let id = assignmentID(from: reminder.url) else { return nil }
        return ReminderRecord(
            identifier: reminder.calendarItemIdentifier,
            assignmentID: id,
            title: reminder.title ?? "",
            dueKey: DueKey.make(from: reminder.dueDateComponents),
            notes: reminder.notes,
            isCompleted: reminder.isCompleted
        )
    }

    // MARK: - 書き込み

    /// 計画を EventKit に適用する。1 件ずつ commit するので、1 件の失敗が他の課題に波及しない。
    func apply(_ plan: SyncPlan, to list: EKCalendar) -> ApplyOutcome {
        var outcome = ApplyOutcome()

        for assignment in plan.adds {
            do {
                try addReminder(assignment, to: list)
                outcome.added += 1
            } catch {
                outcome.failedIDs.insert(Self.assignmentID(fromUID: assignment.uid) ?? assignment.uid)
                outcome.failureMessages.append("\(assignment.title): \(error.localizedDescription)")
            }
        }

        for update in plan.updates {
            do {
                try updateReminder(update)
                outcome.updated += 1
            } catch {
                outcome.failedIDs.insert(update.assignmentID)
                outcome.failureMessages.append("\(update.assignment.title): \(error.localizedDescription)")
            }
        }

        return outcome
    }

    func addReminder(_ assignment: Assignment, to list: EKCalendar) throws {
        let reminder = EKReminder(eventStore: store)
        reminder.title = assignment.title
        reminder.calendar = list
        reminder.url = assignment.url
        reminder.dueDateComponents = Self.dueComponents(for: assignment)
        reminder.notes = Self.notes(for: assignment)

        try store.save(reminder, commit: true)
    }

    private func updateReminder(_ update: ReminderUpdate) throws {
        guard let reminder = store.calendarItem(withIdentifier: update.recordID) as? EKReminder else {
            throw RemindersError.reminderNotFound
        }
        if update.fields.contains(.title) { reminder.title = update.assignment.title }
        if update.fields.contains(.due)   { reminder.dueDateComponents = Self.dueComponents(for: update.assignment) }
        if update.fields.contains(.notes) { reminder.notes = Self.notes(for: update.assignment) }

        try store.save(reminder, commit: true)
    }

    /// 終日課題（VALUE=DATE）は時刻を付けない → リマインダーが「0:00」を表示しない。
    nonisolated static func dueComponents(for assignment: Assignment) -> DateComponents? {
        guard let due = assignment.dueAt else { return nil }
        return DueKey.components(for: due, isAllDay: assignment.isAllDay)
    }

    /// notes はコース名のみ（URL はリマインダーの url フィールドにあるので重複させない）。
    nonisolated static func notes(for assignment: Assignment) -> String? {
        assignment.courseName.isEmpty ? nil : assignment.courseName
    }
}
