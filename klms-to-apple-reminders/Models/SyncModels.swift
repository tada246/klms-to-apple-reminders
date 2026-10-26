import Foundation

// 課題の更新反映（イシュー #7）で使う値型。EventKit に依存しないので単体テストできる。
// 設計は docs/design-issues-4-5-7.md §3 を参照。

/// 同期で Canvas と突き合わせる 3 項目の値。
/// 「Canvas の現在値」「リマインダーの現在値」「前回同期で記録した値（スナップショット）」のどれにも使う。
struct SyncedFields: Codable, Equatable {
    var title: String
    /// 締切の正規化キー（`DueKey`）。
    var dueKey: String?
    /// コース名。空は nil に揃えて比較する。
    var notes: String?

    init(title: String, dueKey: String?, notes: String?) {
        self.title = title
        self.dueKey = dueKey
        self.notes = Self.normalizeNotes(notes)
    }

    init(assignment: Assignment) {
        self.init(
            title: assignment.title,
            dueKey: assignment.dueAt.map { DueKey.make($0, isAllDay: assignment.isAllDay) },
            notes: assignment.courseName
        )
    }

    init(record: ReminderRecord) {
        self.init(title: record.title, dueKey: record.dueKey, notes: record.notes)
    }

    /// 前後の空白・改行は無視し、空なら nil。Reminders アプリが末尾に改行を足しても差分扱いにしない。
    static func normalizeNotes(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// EKReminder の値スナップショット。課題 ID を URL から取り出せたものだけが対象。
struct ReminderRecord: Equatable {
    /// EKReminder.calendarItemIdentifier。更新時にリマインダーを引き直すのに使う。
    let identifier: String
    let assignmentID: String
    let title: String
    let dueKey: String?
    let notes: String?
    let isCompleted: Bool
}

enum SyncField: Hashable {
    case title, due, notes
}

struct ReminderUpdate: Equatable {
    let recordID: String
    let assignmentID: String
    /// 反映する値の元（Canvas の現在値）。
    let assignment: Assignment
    let fields: Set<SyncField>
}

/// `SyncPlanner.plan` の結果。EventKit への適用は `RemindersService.apply` が行う。
struct SyncPlan: Equatable {
    var adds: [Assignment] = []
    var updates: [ReminderUpdate] = []
    /// 適用が **全部成功した場合の** 同期後スナップショット（課題 ID → Canvas の値）。
    /// 失敗した ID は `SyncPlanner.finalSnapshots` で前回の値に戻す。
    var snapshots: [String: SyncedFields] = [:]
    /// 既にリマインダーがあり、変更が無かった課題の数（期間内のものだけ数える）。
    var unchanged = 0
    /// 課題 ID を取り出せず、追加も更新もできなかった課題の数。
    var skippedWithoutID = 0
}

/// 締切の正規化キー。
///
/// `DateComponents` や `Date` をそのまま比べるとタイムゾーン・暦・秒の揺れで誤差分になるため、
/// 端末のタイムゾーンのグレゴリオ暦での表記に落とした文字列で比べる。
/// - 終日: `2026-07-15`
/// - 時刻付き: `2026-07-15T23:59`
enum DueKey {
    /// リマインダーに書き込む締切（`make(from:)` が同じキーに戻せる形）。
    static func components(for date: Date, isAllDay: Bool, timeZone: TimeZone = .current) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // 終日課題は時刻を付けない → リマインダーが「0:00」を表示しない。
        let fields: Set<Calendar.Component> = isAllDay
            ? [.year, .month, .day]
            : [.year, .month, .day, .hour, .minute]
        return calendar.dateComponents(fields, from: date)
    }

    static func make(_ date: Date, isAllDay: Bool, timeZone: TimeZone = .current) -> String {
        // components(for:) は年月日を必ず含むので nil にはならない。
        make(from: components(for: date, isAllDay: isAllDay, timeZone: timeZone)) ?? ""
    }

    /// 年月日が無ければ nil。時が無ければ終日扱い。
    static func make(from components: DateComponents?) -> String? {
        guard let c = components, let y = c.year, let m = c.month, let d = c.day else { return nil }
        if let h = c.hour {
            return String(format: "%04d-%02d-%02dT%02d:%02d", y, m, d, h, c.minute ?? 0)
        }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}
