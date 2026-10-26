import XCTest
@testable import klms_to_apple_reminders

/// URLSession をスタブ化して ICSFeedClient の取得・エラー処理を検証する。
final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class ICSFeedClientTests: XCTestCase {

    private let feedURL = URL(string: "https://lms.example.invalid/feeds/calendars/user_test.ics")!

    private func makeClient() -> ICSFeedClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return ICSFeedClient(feedURL: feedURL, session: URLSession(configuration: config))
    }

    private func respond(status: Int, body: Data) {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
    }

    private let feed = [
        "BEGIN:VCALENDAR",
        // 課題（時刻付き）
        "BEGIN:VEVENT", "UID:event-assignment-1", "DTSTART:20260715T145900Z",
        "SUMMARY:課題A [コースA]", "URL:https://lms.keio.jp/courses/10/assignments/1", "END:VEVENT",
        // 課題（終日）
        "BEGIN:VEVENT", "UID:event-assignment-2", "DTSTART;VALUE=DATE:20260720",
        "SUMMARY:課題B [コースB]", "END:VEVENT",
        // 課題ではないカレンダーイベント
        "BEGIN:VEVENT", "UID:event-calendar-event-9", "DTSTART:20260716T000000Z",
        "SUMMARY:休講のお知らせ", "END:VEVENT",
        // 締切の無い課題
        "BEGIN:VEVENT", "UID:event-assignment-3", "SUMMARY:締切なし", "END:VEVENT",
        "END:VCALENDAR",
    ].joined(separator: "\r\n")

    // MARK: - parseAssignments（純粋関数）

    func testParseAssignmentsKeepsOnlyDatedAssignments() {
        let assignments = ICSFeedClient.parseAssignments(from: feed)
        XCTAssertEqual(assignments.map(\.uid), ["event-assignment-1", "event-assignment-2"])
    }

    func testParseAssignmentsMapsFields() {
        let a = ICSFeedClient.parseAssignments(from: feed)[0]
        XCTAssertEqual(a.title, "課題A")
        XCTAssertEqual(a.courseName, "コースA")
        XCTAssertEqual(a.dueAt, utc(2026, 7, 15, 14, 59))
        XCTAssertFalse(a.isAllDay)
        XCTAssertEqual(a.url?.absoluteString, "https://lms.keio.jp/courses/10/assignments/1")
    }

    func testParseAssignmentsMarksAllDay() {
        XCTAssertTrue(ICSFeedClient.parseAssignments(from: feed)[1].isAllDay)
    }

    func testParseAssignmentsDoesNotApplyWindow() {
        // 期間フィルタは取得側ではかけない（既存リマインダーの更新に窓外の課題も必要なため）
        let old = "BEGIN:VEVENT\nUID:event-assignment-9\nDTSTART:20200101T000000Z\nEND:VEVENT\n"
        XCTAssertEqual(ICSFeedClient.parseAssignments(from: old).count, 1)
    }

    // MARK: - window / filter

    func testWindowBoundsAreOneDayBackAndDaysAhead() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = utc(2026, 7, 10)
        let range = ICSFeedClient.window(daysAhead: 30, now: now, calendar: cal)
        XCTAssertEqual(range.lowerBound, utc(2026, 7, 9))
        XCTAssertEqual(range.upperBound, utc(2026, 8, 9))
    }

    func testFilterKeepsOnlyAssignmentsInsideWindow() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = utc(2026, 7, 10)

        func make(_ id: String, due: Date?) -> Assignment {
            Assignment(uid: id, id: id, title: id, courseName: "", dueAt: due, isAllDay: false, url: nil)
        }
        let all = [
            make("two-days-ago",  due: utc(2026, 7, 8)),
            make("half-day-ago",  due: utc(2026, 7, 9, 12)),
            make("today",         due: now),
            make("at-upper",      due: utc(2026, 8, 9)),
            make("beyond-upper",  due: utc(2026, 8, 10)),
            make("no-due",        due: nil),
        ]
        let kept = ICSFeedClient.filter(all, daysAhead: 30, now: now, calendar: cal).map(\.uid)
        XCTAssertEqual(kept, ["half-day-ago", "today", "at-upper"])
    }

    // MARK: - fetch（URLSession スタブ）

    func testFetchAllAssignmentsParsesResponseBody() async throws {
        respond(status: 200, body: Data(feed.utf8))
        let assignments = try await makeClient().fetchAllAssignments()
        XCTAssertEqual(assignments.count, 2)
    }

    func testFetchBypassesLocalHTTPCache() async throws {
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        _ = try await makeClient().fetchAllAssignments()
        XCTAssertEqual(captured?.cachePolicy, .reloadIgnoringLocalCacheData, "更新を取りこぼさないようキャッシュを使わないこと")
        XCTAssertEqual(captured?.timeoutInterval, 30)
        XCTAssertNil(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer は不要（URL のトークンで認証される）")
    }

    func testFetchThrowsHTTPErrorForNon200() async {
        respond(status: 404, body: Data())
        do {
            _ = try await makeClient().fetchAllAssignments()
            XCTFail("throws すべき")
        } catch ICSFeedError.httpError(let code) {
            XCTAssertEqual(code, 404)
        } catch {
            XCTFail("想定外のエラー: \(error)")
        }
    }

    func testFetchWrapsTransportError() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await makeClient().fetchAllAssignments()
            XCTFail("throws すべき")
        } catch ICSFeedError.networkError {
            // OK
        } catch {
            XCTFail("想定外のエラー: \(error)")
        }
    }

    func testFetchThrowsParseErrorForNonUTF8Body() async {
        respond(status: 200, body: Data([0xFF, 0xFE, 0xFD]))
        do {
            _ = try await makeClient().fetchAllAssignments()
            XCTFail("throws すべき")
        } catch ICSFeedError.parseError {
            // OK
        } catch {
            XCTFail("想定外のエラー: \(error)")
        }
    }
}
