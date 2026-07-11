import XCTest
@testable import klms_to_apple_reminders

/// RemindersService の dedup キー抽出（純粋関数部分）のテスト。
/// EKEventStore は実機依存のためここではテストせず、課題 ID 抽出ロジックのみ検証する。
/// dedup は UID とリマインダー URL の両方から同じ課題数値 ID を取り出せることに依存する。
final class RemindersServiceTests: XCTestCase {

    // MARK: - UID からの ID 抽出

    func testAssignmentIDFromUID() {
        XCTAssertEqual(RemindersService.assignmentID(fromUID: "event-assignment-1269269"), "1269269")
    }

    func testAssignmentIDFromUIDWithDomainSuffix() {
        XCTAssertEqual(RemindersService.assignmentID(fromUID: "event-assignment-456@lms.keio.jp"), "456")
    }

    func testAssignmentIDFromNonAssignmentUIDIsNil() {
        XCTAssertNil(RemindersService.assignmentID(fromUID: "event-calendar-event-999"))
    }

    // MARK: - URL からの ID 抽出

    func testAssignmentIDFromCanonicalURL() {
        let url = URL(string: "https://lms.keio.jp/courses/136629/assignments/1269269")
        XCTAssertEqual(RemindersService.assignmentID(from: url), "1269269")
    }

    func testAssignmentIDFromCalendarURLFragment() {
        // 旧形式（カレンダー URL の #assignment_ フラグメント）でも同じ ID が取れること
        let url = URL(string: "https://lms.keio.jp/calendar?include_contexts=course_136629&month=06#assignment_1269269")
        XCTAssertEqual(RemindersService.assignmentID(from: url), "1269269")
    }

    func testAssignmentIDIgnoresCourseID() {
        // course_136629 の数字を誤って拾わないこと
        let url = URL(string: "https://lms.keio.jp/calendar?include_contexts=course_136629&month=06#assignment_777")
        XCTAssertEqual(RemindersService.assignmentID(from: url), "777")
    }

    func testAssignmentIDFromNilURLIsNil() {
        XCTAssertNil(RemindersService.assignmentID(from: nil))
    }

    // MARK: - 往復（UID と URL が一致すること）

    func testUIDAndURLYieldSameID() {
        let uid = "event-assignment-1270357"
        let url = URL(string: "https://lms.keio.jp/courses/139723/assignments/1270357")
        XCTAssertEqual(RemindersService.assignmentID(fromUID: uid), RemindersService.assignmentID(from: url))
    }
}
