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

    /// リマインダーの notes に埋め込む不可視マーカーの正規表現。
    /// `[klms:<uid>]` の形式で、ICS の UID をそのまま dedup キーとして使う。
    private static let markerRegex = try! NSRegularExpression(pattern: "\\[klms:([^\\]]+)\\]")

    /// notes 末尾に付与する dedup 用マーカー行を生成する。
    /// ICS UID は `event-assignment-123@lms.keio.jp` のような形式で `]` を含まない前提だが、
    /// 抽出側は `[^\]]+` で堅牢に扱う。
    /// 純粋関数（EKEventStore に依存しない）のため nonisolated にし、
    /// MainActor 外（テストなど）からも同期的に呼べるようにする。
    nonisolated static func marker(for uid: String) -> String {
        "[klms:\(uid)]"
    }

    /// notes からマーカーに埋め込まれた UID を抽出する。マーカーが無ければ nil
    /// （ユーザーが手動作成したリマインダーなど、klms 由来でないものは無視する）。
    nonisolated static func extractUID(from notes: String?) -> String? {
        guard let notes else { return nil }
        let range = NSRange(notes.startIndex..<notes.endIndex, in: notes)
        guard let match = markerRegex.firstMatch(in: notes, range: range),
              let uidRange = Range(match.range(at: 1), in: notes) else {
            return nil
        }
        return String(notes[uidRange])
    }

    /// 既存リマインダーの UID 集合を取得する。
    ///
    /// 以前は `submitted`（Canvas API の提出済みフラグ）で重複回避していたが、
    /// .ics フィードには提出済みフラグが存在しないため、ICS の安定 UID を
    /// notes に埋め込んだマーカー（`[klms:<uid>]`）による dedup 方式に変更した。
    ///
    /// 完了済みリマインダーも含めて走査する（isCompleted によるフィルタは行わない）。
    /// これは、完了済みの課題が次回同期時に「未走査」扱いとなって復活してしまう
    /// のを防ぐため。ユーザーが完了にしたリマインダーは再作成されるべきではない。
    func existingUIDs(in list: EKCalendar) async -> Set<String> {
        let predicate = store.predicateForReminders(in: [list])
        return await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { reminders in
                let uids = Set((reminders ?? []).compactMap { Self.extractUID(from: $0.notes) })
                cont.resume(returning: uids)
            }
        }
    }

    func addReminder(_ assignment: Assignment, to list: EKCalendar) throws {
        let reminder = EKReminder(eventStore: store)
        reminder.title = assignment.title
        reminder.calendar = list
        reminder.url = assignment.url

        if let due = assignment.dueAt {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: due)
            reminder.dueDateComponents = comps
        }

        var notesLines: [String] = []
        if !assignment.courseName.isEmpty {
            notesLines.append(assignment.courseName)
        }
        if let url = assignment.url {
            notesLines.append(url.absoluteString)
        }
        // dedup の要となるマーカー行。notes が他に空でも必ず付与する。
        notesLines.append(Self.marker(for: assignment.uid))
        reminder.notes = notesLines.joined(separator: "\n")

        try store.save(reminder, commit: true)
    }
}
