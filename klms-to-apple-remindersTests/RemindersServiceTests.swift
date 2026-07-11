import XCTest
@testable import klms_to_apple_reminders

/// RemindersService のマーカー生成・抽出ロジック（純粋関数部分）のテスト。
/// EKEventStore は実機依存のためここではテストせず、`marker(for:)` /
/// `extractUID(from:)` の静的ヘルパーのみを検証する。
final class RemindersServiceTests: XCTestCase {

    // MARK: - marker(for:)

    func testMarkerFormat() {
        let marker = RemindersService.marker(for: "event-assignment-123@lms.keio.jp")
        XCTAssertEqual(marker, "[klms:event-assignment-123@lms.keio.jp]")
    }

    // MARK: - extractUID(from:)

    func testExtractUIDFromMarkerOnly() {
        let notes = "[klms:event-assignment-123@lms.keio.jp]"
        XCTAssertEqual(RemindersService.extractUID(from: notes), "event-assignment-123@lms.keio.jp")
    }

    func testExtractUIDFromNotesWithCourseAndURL() {
        let notes = """
        情報理論
        https://lms.keio.jp/courses/123/assignments/456
        [klms:event-assignment-456@lms.keio.jp]
        """
        XCTAssertEqual(RemindersService.extractUID(from: notes), "event-assignment-456@lms.keio.jp")
    }

    func testExtractUIDReturnsNilWhenNoMarker() {
        let notes = "買い物リスト\n牛乳を買う"
        XCTAssertNil(RemindersService.extractUID(from: notes))
    }

    func testExtractUIDReturnsNilWhenNotesIsNil() {
        XCTAssertNil(RemindersService.extractUID(from: nil))
    }

    func testExtractUIDReturnsNilForEmptyString() {
        XCTAssertNil(RemindersService.extractUID(from: ""))
    }

    func testMarkerRoundTrip() {
        let uid = "event-assignment-789@lms.keio.jp"
        let notes = "コース名\n\(RemindersService.marker(for: uid))"
        XCTAssertEqual(RemindersService.extractUID(from: notes), uid)
    }

    func testExtractUIDIgnoresUnrelatedBrackets() {
        // klms: プレフィックスの無い角括弧は無視すること
        let notes = "[note] これはメモです\n[klms:event-assignment-999@lms.keio.jp]"
        XCTAssertEqual(RemindersService.extractUID(from: notes), "event-assignment-999@lms.keio.jp")
    }
}
