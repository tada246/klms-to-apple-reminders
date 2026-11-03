import EventKit
import XCTest
@testable import klms_to_apple_reminders

/// DueKey / SnapshotStore / SyncResult / RemindersService の値変換のテスト。
final class SyncSupportTests: XCTestCase {

    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private let utc = TimeZone(identifier: "UTC")!

    /// 2026-07-15 14:59:00 UTC（= 東京 23:59）
    private var instant: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return cal.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 14, minute: 59))!
    }

    // MARK: - DueKey

    func testDueKeyTimedUsesGivenTimeZone() {
        XCTAssertEqual(DueKey.make(instant, isAllDay: false, timeZone: utc), "2026-07-15T14:59")
        XCTAssertEqual(DueKey.make(instant, isAllDay: false, timeZone: tokyo), "2026-07-15T23:59")
    }

    func testDueKeyAllDayHasNoTime() {
        XCTAssertEqual(DueKey.make(instant, isAllDay: true, timeZone: tokyo), "2026-07-15")
    }

    func testDueKeyAllDayDateRollsOverWithTimeZone() {
        // UTC 20:00 は東京では翌日
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        let lateUTC = cal.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 20))!
        XCTAssertEqual(DueKey.make(lateUTC, isAllDay: true, timeZone: tokyo), "2026-07-16")
    }

    func testDueKeyFromComponents() {
        XCTAssertEqual(DueKey.make(from: DateComponents(year: 2026, month: 7, day: 5, hour: 9, minute: 5)), "2026-07-05T09:05")
        XCTAssertEqual(DueKey.make(from: DateComponents(year: 2026, month: 7, day: 5)), "2026-07-05")
        XCTAssertEqual(DueKey.make(from: DateComponents(year: 2026, month: 7, day: 5, hour: 9)), "2026-07-05T09:00")
    }

    func testDueKeyFromIncompleteComponentsIsNil() {
        XCTAssertNil(DueKey.make(from: nil))
        XCTAssertNil(DueKey.make(from: DateComponents(hour: 9, minute: 0)))
    }

    func testDueKeyRoundTripsThroughComponents() {
        for allDay in [true, false] {
            let comps = DueKey.components(for: instant, isAllDay: allDay, timeZone: tokyo)
            XCTAssertEqual(DueKey.make(from: comps), DueKey.make(instant, isAllDay: allDay, timeZone: tokyo))
        }
    }

    func testDueComponentsForAllDayOmitTime() {
        let comps = DueKey.components(for: instant, isAllDay: true, timeZone: tokyo)
        XCTAssertNil(comps.hour)
        XCTAssertNil(comps.minute)
        XCTAssertEqual(comps.day, 15)
    }

    // MARK: - SyncedFields

    func testSyncedFieldsNormalizesNotes() {
        XCTAssertNil(SyncedFields(title: "t", dueKey: nil, notes: "").notes)
        XCTAssertNil(SyncedFields(title: "t", dueKey: nil, notes: " \n ").notes)
        XCTAssertEqual(SyncedFields(title: "t", dueKey: nil, notes: "コース\n").notes, "コース")
    }

    func testSyncedFieldsFromAssignment() {
        let a = Assignment(uid: "event-assignment-1", id: "event-assignment-1", title: "課題", courseName: "コース",
                           dueAt: instant, isAllDay: false, url: nil)
        let f = SyncedFields(assignment: a)
        XCTAssertEqual(f.title, "課題")
        XCTAssertEqual(f.notes, "コース")
        XCTAssertEqual(f.dueKey, DueKey.make(instant, isAllDay: false))
    }

    func testSyncedFieldsCodableRoundTrip() throws {
        let f = SyncedFields(title: "課題", dueKey: "2026-07-15T23:59", notes: "コース")
        let decoded = try JSONDecoder().decode(SyncedFields.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(decoded, f)
    }

    // MARK: - SnapshotStore

    private func makeStore() -> (UserDefaultsSnapshotStore, UserDefaults, String) {
        let suite = "klms-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (UserDefaultsSnapshotStore(defaults: defaults), defaults, suite)
    }

    func testSnapshotStoreEmptyByDefault() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(store.load().isEmpty)
    }

    func testSnapshotStoreSaveAndLoad() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshots = ["1": SyncedFields(title: "A", dueKey: "2026-07-15", notes: nil),
                         "2": SyncedFields(title: "B", dueKey: nil, notes: "コース")]
        store.save(snapshots)
        XCTAssertEqual(store.load(), snapshots)
    }

    func testSnapshotStoreSaveOverwrites() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.save(["1": SyncedFields(title: "A", dueKey: nil, notes: nil)])
        store.save(["2": SyncedFields(title: "B", dueKey: nil, notes: nil)])
        XCTAssertEqual(Set(store.load().keys), ["2"])
    }

    func testSnapshotStoreCorruptedDataLoadsAsEmpty() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: "syncSnapshots")
        XCTAssertTrue(store.load().isEmpty)
    }

    // MARK: - SyncResult

    func testSyncResultSummary() {
        let r = SyncResult(added: 2, updated: 1, unchanged: 10, failed: 0, timestamp: Date())
        XCTAssertEqual(r.summary, "追加2・更新1・変更なし10")
    }

    func testSyncResultSummaryShowsFailuresOnlyWhenPresent() {
        let r = SyncResult(added: 0, updated: 0, unchanged: 3, failed: 2, timestamp: Date())
        XCTAssertEqual(r.summary, "追加0・更新0・変更なし3・失敗2")
    }

    // MARK: - RemindersService の値変換（EventKit のオブジェクトは作るだけで保存しない）

    func testRecordFromReminder() {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = "課題A"
        reminder.url = URL(string: "https://lms.keio.jp/courses/10/assignments/1269269")
        reminder.dueDateComponents = DateComponents(year: 2026, month: 7, day: 15, hour: 23, minute: 59)
        reminder.notes = "コースA"
        reminder.isCompleted = true

        let record = RemindersService.record(from: reminder)
        XCTAssertEqual(record?.assignmentID, "1269269")
        XCTAssertEqual(record?.title, "課題A")
        XCTAssertEqual(record?.dueKey, "2026-07-15T23:59")
        XCTAssertEqual(record?.notes, "コースA")
        XCTAssertEqual(record?.isCompleted, true)
    }

    func testRecordFromReminderWithoutAssignmentURLIsNil() {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = "手で作ったリマインダー"
        XCTAssertNil(RemindersService.record(from: reminder))
    }

    func testDueComponentsAndNotesForAssignment() {
        let timed = Assignment(uid: "event-assignment-1", id: "x", title: "t", courseName: "コース",
                               dueAt: instant, isAllDay: false, url: nil)
        let allDay = Assignment(uid: "event-assignment-2", id: "y", title: "t", courseName: "",
                                dueAt: instant, isAllDay: true, url: nil)
        XCTAssertNotNil(RemindersService.dueComponents(for: timed)?.hour)
        XCTAssertNil(RemindersService.dueComponents(for: allDay)?.hour)
        XCTAssertEqual(RemindersService.notes(for: timed), "コース")
        XCTAssertNil(RemindersService.notes(for: allDay))
    }
}
