import XCTest
@testable import klms_to_apple_reminders

/// ICS パーサ（行アンフォールディング・VEVENT 抽出・日時 3 形式・タイトル分割・URL 組み立て）のテスト。
/// 前提とするフォーマットは ICSFeedClient.swift 冒頭コメントの VEVENT サンプルと同じ。
final class ICSParserTests: XCTestCase {

    // MARK: - Helpers

    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
    }

    private func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
    }

    private let sampleFeed = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Instructure//Canvas//EN",
        "BEGIN:VEVENT",
        "DTSTAMP:20260710T030201Z",
        "DTSTART:20260715T145900Z",
        "DTEND:20260715T145900Z",
        "UID:event-assignment-123456@lms.keio.jp",
        "SUMMARY:レポート課題1 [情報基礎論]",
        "DESCRIPTION:第1回レポート課題です。\\n提出期限厳守。",
        "URL:https://lms.keio.jp/courses/1000/assignments/123456",
        "END:VEVENT",
        "END:VCALENDAR",
    ].joined(separator: "\r\n") + "\r\n"

    // MARK: - unfold

    func testUnfoldJoinsContinuationLines() {
        let text = "SUMMARY:AAA\r\n BBB\r\n\tCCC\r\nUID:x"
        XCTAssertEqual(ICSParser.unfold(text), "SUMMARY:AAABBBCCC\nUID:x")
    }

    func testUnfoldKeepsNormalLines() {
        XCTAssertEqual(ICSParser.unfold("A:1\nB:2\n"), "A:1\nB:2\n")
    }

    // MARK: - parseVEvents

    func testParseVEventsExtractsFields() {
        let events = ICSParser.parseVEvents(from: sampleFeed)
        XCTAssertEqual(events.count, 1)
        guard let e = events.first else { return XCTFail("VEVENT が抽出されていない") }
        XCTAssertEqual(e.uid, "event-assignment-123456@lms.keio.jp")
        XCTAssertEqual(e.summary, "レポート課題1 [情報基礎論]")
        XCTAssertEqual(e.dtStart, utc(2026, 7, 15, 14, 59))
        XCTAssertFalse(e.isAllDay)
        XCTAssertEqual(e.url, "https://lms.keio.jp/courses/1000/assignments/123456")
    }

    func testParseVEventsIgnoresPropertiesOutsideVEvent() {
        let text = "BEGIN:VCALENDAR\nUID:outside\nBEGIN:VEVENT\nUID:inside\nEND:VEVENT\nEND:VCALENDAR\n"
        let events = ICSParser.parseVEvents(from: text)
        XCTAssertEqual(events.map(\.uid), ["inside"])
    }

    func testParseVEventsSkipsEventWithoutUID() {
        let text = "BEGIN:VEVENT\nSUMMARY:no uid\nEND:VEVENT\nBEGIN:VEVENT\nUID:ok\nEND:VEVENT\n"
        XCTAssertEqual(ICSParser.parseVEvents(from: text).map(\.uid), ["ok"])
    }

    func testParseVEventsHandlesLFLineEndingsAndMultipleEvents() {
        let text = "BEGIN:VEVENT\nUID:a\nEND:VEVENT\nBEGIN:VEVENT\nUID:b\nEND:VEVENT\n"
        XCTAssertEqual(ICSParser.parseVEvents(from: text).map(\.uid), ["a", "b"])
    }

    func testParseVEventsHandlesFoldedSummary() {
        let text = "BEGIN:VEVENT\r\nUID:a\r\nSUMMARY:長い課題名 \r\n [コース名]\r\nEND:VEVENT\r\n"
        XCTAssertEqual(ICSParser.parseVEvents(from: text).first?.summary, "長い課題名 [コース名]")
    }

    func testParseVEventsMarksAllDay() {
        let text = "BEGIN:VEVENT\nUID:a\nDTSTART;VALUE=DATE:20260720\nEND:VEVENT\n"
        guard let e = ICSParser.parseVEvents(from: text).first else { return XCTFail("VEVENT が抽出されていない") }
        XCTAssertTrue(e.isAllDay)
        XCTAssertEqual(e.dtStart, local(2026, 7, 20))
    }

    // MARK: - parseDate

    func testParseDateUTC() {
        XCTAssertEqual(ICSParser.parseDate(value: "20260715T145900Z", params: [:]), utc(2026, 7, 15, 14, 59))
    }

    func testParseDateAllDayIsLocalMidnight() {
        XCTAssertEqual(ICSParser.parseDate(value: "20260715", params: ["VALUE": "DATE"]), local(2026, 7, 15))
    }

    func testParseDateWithTZID() {
        // 東京 2026-07-15 23:59 = UTC 14:59
        let date = ICSParser.parseDate(value: "20260715T235900", params: ["TZID": "Asia/Tokyo"])
        XCTAssertEqual(date, utc(2026, 7, 15, 14, 59))
    }

    func testParseDateWithUnknownTZIDFallsBackToLocal() {
        let date = ICSParser.parseDate(value: "20260715T235900", params: ["TZID": "Not/AZone"])
        XCTAssertEqual(date, local(2026, 7, 15, 23, 59))
    }

    func testParseDateWithoutTZIDIsLocal() {
        XCTAssertEqual(ICSParser.parseDate(value: "20260715T091500", params: [:]), local(2026, 7, 15, 9, 15))
    }

    func testParseDateGarbageIsNil() {
        XCTAssertNil(ICSParser.parseDate(value: "not-a-date", params: [:]))
    }

    // MARK: - splitProperty / unescape

    func testSplitPropertySplitsOnFirstColonOnly() {
        let parsed = ICSParser.splitProperty("URL:https://lms.keio.jp/a?b=c")
        XCTAssertEqual(parsed?.name, "URL")
        XCTAssertEqual(parsed?.value, "https://lms.keio.jp/a?b=c")
    }

    func testSplitPropertyParsesParams() {
        let parsed = ICSParser.splitProperty("DTSTART;TZID=Asia/Tokyo:20260715T235900")
        XCTAssertEqual(parsed?.name, "DTSTART")
        XCTAssertEqual(parsed?.params["TZID"], "Asia/Tokyo")
        XCTAssertEqual(parsed?.value, "20260715T235900")
    }

    func testSplitPropertyWithoutColonIsNil() {
        XCTAssertNil(ICSParser.splitProperty("no colon here"))
    }

    func testUnescape() {
        XCTAssertEqual(ICSParser.unescape("a\\nb\\Nc"), "a\nb\nc")
        XCTAssertEqual(ICSParser.unescape("a\\,b\\;c"), "a,b;c")
        XCTAssertEqual(ICSParser.unescape("back\\\\slash"), "back\\slash")
        XCTAssertEqual(ICSParser.unescape("plain"), "plain")
    }

    // MARK: - splitTitleAndCourse

    func testSplitTitleAndCourseSimple() {
        let (title, course) = ICSParser.splitTitleAndCourse(from: "レポート課題1 [情報基礎論]")
        XCTAssertEqual(title, "レポート課題1")
        XCTAssertEqual(course, "情報基礎論")
    }

    func testSplitTitleAndCourseStripsPeriodTeacherAndCampus() {
        let (title, course) = ICSParser.splitTitleAndCourse(from: "第1回レポート [[月1]山田　統計基礎[DS1] [日吉 A101]]")
        XCTAssertEqual(title, "第1回レポート")
        XCTAssertEqual(course, "統計基礎[DS1]")
    }

    func testSplitTitleAndCourseKeepsBracketsInsideTitle() {
        let (title, course) = ICSParser.splitTitleAndCourse(from: "任意課題[慶應義塾史展示館] [[火2]鈴木　歴史学 [三田]]")
        XCTAssertEqual(title, "任意課題[慶應義塾史展示館]")
        XCTAssertEqual(course, "歴史学")
    }

    func testSplitTitleAndCourseWithoutBrackets() {
        let (title, course) = ICSParser.splitTitleAndCourse(from: "  ブラケット無し  ")
        XCTAssertEqual(title, "ブラケット無し")
        XCTAssertEqual(course, "")
    }

    func testSplitTitleAndCourseUnbalancedBracketsLeaveSummaryAsTitle() {
        let (title, course) = ICSParser.splitTitleAndCourse(from: "A [B")
        XCTAssertEqual(title, "A [B")
        XCTAssertEqual(course, "")
    }

    func testSplitTitleAndCourseOnlyBracketKeepsSummaryAsTitle() {
        // タイトルが空になる場合は元の summary をタイトルに使う
        let (title, _) = ICSParser.splitTitleAndCourse(from: "[Foo]")
        XCTAssertEqual(title, "[Foo]")
    }

    // MARK: - assignmentPageURL

    func testAssignmentPageURLFromCalendarURL() {
        let raw = "https://lms.keio.jp/calendar?include_contexts=course_136629&month=06#assignment_1269269"
        XCTAssertEqual(
            ICSParser.assignmentPageURL(rawURL: raw, uid: "event-assignment-1269269")?.absoluteString,
            "https://lms.keio.jp/courses/136629/assignments/1269269"
        )
    }

    func testAssignmentPageURLKeepsCanonicalRawURL() {
        let raw = "https://lms.keio.jp/courses/1000/assignments/123456"
        XCTAssertEqual(ICSParser.assignmentPageURL(rawURL: raw, uid: "event-assignment-123456")?.absoluteString, raw)
    }

    func testAssignmentPageURLFallsBackToUID() {
        XCTAssertEqual(
            ICSParser.assignmentPageURL(rawURL: nil, uid: "event-assignment-777@lms.keio.jp")?.absoluteString,
            "https://lms.keio.jp/assignments/777"
        )
    }

    func testAssignmentPageURLNilWhenNothingUsable() {
        XCTAssertNil(ICSParser.assignmentPageURL(rawURL: nil, uid: "event-calendar-event-1"))
    }

    func testAssignmentPageURLRoundTripsToSameAssignmentID() {
        // 組み立てた URL からも、UID と同じ課題 ID が取れること（重複判定の前提）
        let uid = "event-assignment-1269269"
        let url = ICSParser.assignmentPageURL(
            rawURL: "https://lms.keio.jp/calendar?include_contexts=course_136629#assignment_1269269",
            uid: uid
        )
        XCTAssertEqual(RemindersService.assignmentID(from: url), RemindersService.assignmentID(fromUID: uid))
    }
}
