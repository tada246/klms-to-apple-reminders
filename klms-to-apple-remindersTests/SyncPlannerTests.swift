import XCTest
@testable import klms_to_apple_reminders

/// SyncPlanner（追加／更新／維持の判定）のテスト。EventKit には触れない。
/// 判定表は SyncPlanner.swift 冒頭と docs/design-issues-4-5-7.md §3.3 に対応する。
final class SyncPlannerTests: XCTestCase {

    // MARK: - Fixtures

    private let now = Date(timeIntervalSince1970: 1_784_000_000)   // 固定の「現在」
    private var window: ClosedRange<Date> { ICSFeedClient.window(daysAhead: 30, now: now) }

    private func days(_ n: Double) -> Date { now.addingTimeInterval(n * 86_400) }

    private func assignment(
        _ id: Int,
        title: String = "課題",
        course: String = "コースA",
        due: Date? = nil,
        allDay: Bool = false
    ) -> Assignment {
        let uid = "event-assignment-\(id)"
        return Assignment(
            uid: uid, id: uid, title: title, courseName: course,
            dueAt: due ?? days(5), isAllDay: allDay,
            url: URL(string: "https://lms.keio.jp/courses/1/assignments/\(id)")
        )
    }

    /// リマインダーの現在値を、Canvas の値 `a` から作る（個別に上書き可能）。
    private func record(
        for a: Assignment,
        recordID: String? = nil,
        title: String? = nil,
        dueKey: String?? = nil,
        notes: String?? = nil,
        completed: Bool = false
    ) -> ReminderRecord {
        let f = SyncedFields(assignment: a)
        return ReminderRecord(
            identifier: recordID ?? "rec-\(a.uid)",
            assignmentID: RemindersService.assignmentID(fromUID: a.uid)!,
            title: title ?? f.title,
            dueKey: dueKey ?? f.dueKey,
            notes: notes ?? f.notes,
            isCompleted: completed
        )
    }

    private func snapshot(_ a: Assignment) -> [String: SyncedFields] {
        [RemindersService.assignmentID(fromUID: a.uid)!: SyncedFields(assignment: a)]
    }

    private func plan(
        feed: [Assignment],
        records: [ReminderRecord] = [],
        snapshots: [String: SyncedFields] = [:]
    ) -> SyncPlan {
        SyncPlanner.plan(feed: feed, records: records, snapshots: snapshots, window: window)
    }

    // MARK: - 追加

    func testAddsNewAssignmentInsideWindow() {
        let a = assignment(1)
        let p = plan(feed: [a])
        XCTAssertEqual(p.adds, [a])
        XCTAssertEqual(p.snapshots["1"], SyncedFields(assignment: a))
        XCTAssertTrue(p.updates.isEmpty)
    }

    func testDoesNotAddAssignmentOutsideWindow() {
        let p = plan(feed: [assignment(1, due: days(60)), assignment(2, due: days(-5))])
        XCTAssertTrue(p.adds.isEmpty)
        XCTAssertTrue(p.snapshots.isEmpty)
    }

    func testAddsAssignmentDueWithinOneDayAgo() {
        // 締切直後の未提出課題を取りこぼさない（過去 1 日は窓に含む）
        XCTAssertEqual(plan(feed: [assignment(1, due: days(-0.5))]).adds.count, 1)
    }

    func testSkipsAssignmentWithoutExtractableID() {
        let a = Assignment(uid: "event-assignment-abc", id: "x", title: "t", courseName: "",
                           dueAt: days(1), isAllDay: false, url: nil)
        let p = plan(feed: [a])
        XCTAssertTrue(p.adds.isEmpty)
        XCTAssertEqual(p.skippedWithoutID, 1)
    }

    func testDuplicateUIDInFeedUsesFirstOnly() {
        let first = assignment(1, title: "最初")
        let second = assignment(1, title: "二番目")
        XCTAssertEqual(plan(feed: [first, second]).adds.map(\.title), ["最初"])
    }

    // MARK: - 変更なし

    func testNoChangeWhenFeedEqualsReminder() {
        let a = assignment(1)
        let p = plan(feed: [a], records: [record(for: a)], snapshots: snapshot(a))
        XCTAssertTrue(p.adds.isEmpty)
        XCTAssertTrue(p.updates.isEmpty)
        XCTAssertEqual(p.unchanged, 1)
        XCTAssertEqual(p.snapshots["1"], SyncedFields(assignment: a))
    }

    func testUnchangedCountsOnlyAssignmentsInsideWindow() {
        let inside = assignment(1)
        let outside = assignment(2, due: days(-40))
        let p = plan(feed: [inside, outside], records: [record(for: inside), record(for: outside)])
        XCTAssertEqual(p.unchanged, 1)
    }

    func testEmptyNotesAndNilNotesAreEqual() {
        let a = assignment(1, course: "")
        let p = plan(feed: [a], records: [record(for: a, notes: .some("  \n"))], snapshots: snapshot(a))
        XCTAssertTrue(p.updates.isEmpty)
    }

    // MARK: - Canvas だけが変わった → 更新

    func testUpdatesDueWhenOnlyCanvasChanged() {
        let old = assignment(1, due: days(5))
        let new = assignment(1, due: days(8))
        let p = plan(feed: [new], records: [record(for: old)], snapshots: snapshot(old))
        guard let update = p.updates.first else { return XCTFail("更新が計画されていない") }
        XCTAssertEqual(p.updates.count, 1)
        XCTAssertEqual(update.fields, [.due])
        XCTAssertEqual(update.recordID, "rec-event-assignment-1")
        XCTAssertEqual(update.assignment, new)
        XCTAssertEqual(p.snapshots["1"], SyncedFields(assignment: new))
    }

    func testUpdatesTitleWhenOnlyCanvasChanged() {
        let old = assignment(1, title: "旧タイトル")
        let new = assignment(1, title: "新タイトル")
        let p = plan(feed: [new], records: [record(for: old)], snapshots: snapshot(old))
        XCTAssertEqual(p.updates.first?.fields, [.title])
    }

    func testUpdatesNotesWhenCourseChanged() {
        let old = assignment(1, course: "旧コース")
        let new = assignment(1, course: "新コース")
        let p = plan(feed: [new], records: [record(for: old)], snapshots: snapshot(old))
        XCTAssertEqual(p.updates.first?.fields, [.notes])
    }

    func testUpdatesMultipleFieldsAtOnce() {
        let old = assignment(1, title: "旧", course: "旧コース", due: days(5))
        let new = assignment(1, title: "新", course: "新コース", due: days(9))
        let p = plan(feed: [new], records: [record(for: old)], snapshots: snapshot(old))
        XCTAssertEqual(p.updates.first?.fields, [.title, .notes, .due])
    }

    func testAllDayToTimedSwitchIsDueUpdate() {
        let old = assignment(1, due: days(5), allDay: true)
        let new = assignment(1, due: days(5), allDay: false)
        let p = plan(feed: [new], records: [record(for: old)], snapshots: snapshot(old))
        XCTAssertEqual(p.updates.first?.fields, [.due])
    }

    // MARK: - ユーザー編集を守る

    func testKeepsUserEditedTitleWhenCanvasUnchanged() {
        let a = assignment(1, title: "Canvas の題")
        let p = plan(feed: [a], records: [record(for: a, title: "自分で直した題")], snapshots: snapshot(a))
        XCTAssertTrue(p.updates.isEmpty)
    }

    func testKeepsUserEditedNotesWhenCanvasUnchanged() {
        let a = assignment(1)
        let p = plan(feed: [a], records: [record(for: a, notes: .some("コースA\n自分のメモ"))], snapshots: snapshot(a))
        XCTAssertTrue(p.updates.isEmpty)
    }

    func testKeepsUserEditedDueWhenCanvasUnchanged() {
        let a = assignment(1, due: days(5))
        let early = DueKey.make(days(3), isAllDay: false)
        let p = plan(feed: [a], records: [record(for: a, dueKey: .some(early))], snapshots: snapshot(a))
        XCTAssertTrue(p.updates.isEmpty, "Canvas が変わっていなければ、ユーザーが前倒しにした締切は維持する")
    }

    func testKeepsUserEditedTitleEvenWhenCanvasAlsoChanged() {
        let old = assignment(1, title: "旧")
        let new = assignment(1, title: "新")
        let p = plan(feed: [new], records: [record(for: old, title: "自分の題")], snapshots: snapshot(old))
        XCTAssertTrue(p.updates.isEmpty, "タイトルはユーザー編集を優先")
        XCTAssertEqual(p.snapshots["1"]?.title, "新", "スナップショットは Canvas の最新値に進める")
    }

    func testCanvasDueChangeWinsOverUserEditedDue() {
        let old = assignment(1, due: days(5))
        let new = assignment(1, due: days(9))
        let userDue = DueKey.make(days(3), isAllDay: false)
        let p = plan(feed: [new], records: [record(for: old, dueKey: .some(userDue))], snapshots: snapshot(old))
        XCTAssertEqual(p.updates.first?.fields, [.due], "公式締切が動いたら、ユーザー編集があっても Canvas に合わせる")
    }

    func testUserEditOfOneFieldDoesNotBlockUpdateOfAnother() {
        let old = assignment(1, title: "旧", due: days(5))
        let new = assignment(1, title: "旧", due: days(9))      // Canvas は締切だけ変更
        let p = plan(feed: [new], records: [record(for: old, title: "自分の題")], snapshots: snapshot(old))
        XCTAssertEqual(p.updates.first?.fields, [.due])
    }

    // MARK: - スナップショットが無い（この機能の導入前に作られたリマインダー）

    func testLegacyReminderGetsDueUpdatedOnce() {
        let old = assignment(1, due: days(5))
        let new = assignment(1, due: days(8))
        let p = plan(feed: [new], records: [record(for: old)], snapshots: [:])
        XCTAssertEqual(p.updates.first?.fields, [.due])
        XCTAssertEqual(p.snapshots["1"], SyncedFields(assignment: new), "以後は保護対象になる")
    }

    func testLegacyReminderKeepsTitleAndNotesButSeedsSnapshot() {
        let a = assignment(1, title: "Canvas の題", course: "コースA")
        let p = plan(feed: [a], records: [record(for: a, title: "手で直した題", notes: .some("手書きメモ"))], snapshots: [:])
        XCTAssertTrue(p.updates.isEmpty)
        XCTAssertEqual(p.snapshots["1"], SyncedFields(assignment: a))
    }

    func testLegacyReminderWithMatchingValuesIsUnchanged() {
        let a = assignment(1)
        let p = plan(feed: [a], records: [record(for: a)], snapshots: [:])
        XCTAssertTrue(p.updates.isEmpty)
        XCTAssertEqual(p.unchanged, 1)
    }

    // MARK: - 完了済み

    func testCompletedReminderIsNeverModified() {
        let old = assignment(1, title: "旧", due: days(5))
        let new = assignment(1, title: "新", due: days(9))
        let p = plan(feed: [new], records: [record(for: old, completed: true)], snapshots: snapshot(old))
        XCTAssertTrue(p.updates.isEmpty)
        XCTAssertTrue(p.adds.isEmpty)
        XCTAssertEqual(p.snapshots["1"], SyncedFields(assignment: old), "完了済みのスナップショットは据え置き")
    }

    func testCompletedReminderPreventsReAdd() {
        let a = assignment(1)
        let p = plan(feed: [a], records: [record(for: a, completed: true)])
        XCTAssertTrue(p.adds.isEmpty, "完了にした課題は復活させない")
    }

    func testDuplicateRecordsPreferIncompleteOne() {
        let old = assignment(1, due: days(5))
        let new = assignment(1, due: days(8))
        let done = record(for: old, recordID: "done", completed: true)
        let open = record(for: old, recordID: "open")
        for records in [[done, open], [open, done]] {
            let p = plan(feed: [new], records: records, snapshots: snapshot(old))
            XCTAssertEqual(p.updates.map(\.recordID), ["open"])
            XCTAssertTrue(p.adds.isEmpty)
        }
    }

    // MARK: - 期間外

    func testExistingReminderIsUpdatedEvenWhenDueMovesOutsideWindow() {
        let old = assignment(1, due: days(5))
        let moved = assignment(1, due: days(80))     // 窓（30 日）の外へ延期
        let p = plan(feed: [moved], records: [record(for: old)], snapshots: snapshot(old))
        XCTAssertEqual(p.updates.first?.fields, [.due])
    }

    func testReminderMissingFromFeedKeepsPreviousSnapshot() {
        let a = assignment(1)
        let p = plan(feed: [], records: [record(for: a)], snapshots: snapshot(a))
        XCTAssertTrue(p.updates.isEmpty)
        XCTAssertEqual(p.snapshots["1"], SyncedFields(assignment: a), "フィードから消えても記録は残す（放置方針）")
    }

    func testSnapshotWithoutReminderIsPruned() {
        let gone = assignment(9)
        let p = plan(feed: [], records: [], snapshots: snapshot(gone))
        XCTAssertTrue(p.snapshots.isEmpty)
    }

    func testDeletedReminderIsReAddedAndSnapshotRenewed() {
        let a = assignment(1)
        let stale = SyncedFields(title: "古い", dueKey: "2000-01-01", notes: nil)
        let p = plan(feed: [a], records: [], snapshots: ["1": stale])
        XCTAssertEqual(p.adds, [a])
        XCTAssertEqual(p.snapshots["1"], SyncedFields(assignment: a))
    }

    // MARK: - finalSnapshots

    func testFinalSnapshotsTakesPlannedValuesOnSuccess() {
        let old = assignment(1, due: days(5))
        let new = assignment(1, due: days(8))
        let p = plan(feed: [new], records: [record(for: old)], snapshots: snapshot(old))
        let result = SyncPlanner.finalSnapshots(plan: p, previous: snapshot(old), failedIDs: [])
        XCTAssertEqual(result["1"], SyncedFields(assignment: new))
    }

    func testFinalSnapshotsRevertsFailedUpdateToPrevious() {
        let old = assignment(1, due: days(5))
        let new = assignment(1, due: days(8))
        let p = plan(feed: [new], records: [record(for: old)], snapshots: snapshot(old))
        let result = SyncPlanner.finalSnapshots(plan: p, previous: snapshot(old), failedIDs: ["1"])
        XCTAssertEqual(result["1"], SyncedFields(assignment: old), "失敗したら次回やり直せるよう前回の値に戻す")
    }

    func testFinalSnapshotsOmitsFailedAdd() {
        let p = plan(feed: [assignment(1)])
        XCTAssertTrue(SyncPlanner.finalSnapshots(plan: p, previous: [:], failedIDs: ["1"]).isEmpty)
    }
}
