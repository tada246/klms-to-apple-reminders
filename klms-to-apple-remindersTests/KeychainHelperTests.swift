import XCTest
@testable import klms_to_apple_reminders

final class KeychainHelperTests: XCTestCase {

    override func setUp() {
        super.setUp()
        KeychainHelper.deleteFeedURL()
    }

    override func tearDown() {
        KeychainHelper.deleteFeedURL()
        super.tearDown()
    }

    // MARK: - 保存・読み込み

    func testSaveAndLoadFeedURL() throws {
        let url = "https://lms.keio.jp/feeds/calendars/user_abc123.ics"
        try KeychainHelper.saveFeedURL(url)
        XCTAssertEqual(KeychainHelper.loadFeedURL(), url, "保存したフィード URL が正しく読み込めること")
    }

    func testLoadReturnsNilWhenEmpty() {
        XCTAssertNil(KeychainHelper.loadFeedURL(), "URL が未保存の場合 nil を返すこと")
    }

    func testOverwrite() throws {
        try KeychainHelper.saveFeedURL("https://lms.keio.jp/feeds/calendars/user_first.ics")
        try KeychainHelper.saveFeedURL("https://lms.keio.jp/feeds/calendars/user_second.ics")
        XCTAssertEqual(
            KeychainHelper.loadFeedURL(),
            "https://lms.keio.jp/feeds/calendars/user_second.ics",
            "上書き保存が正しく動作すること"
        )
    }

    func testDelete() throws {
        try KeychainHelper.saveFeedURL("https://lms.keio.jp/feeds/calendars/user_abc.ics")
        KeychainHelper.deleteFeedURL()
        XCTAssertNil(KeychainHelper.loadFeedURL(), "削除後は nil を返すこと")
    }

    func testURLNotCorrupted() throws {
        // 秘密トークンを含む長い URL が文字化けなく保存・読み込みできること
        let url = "https://lms.keio.jp/feeds/calendars/user_ABCdef0123456789ghijKLMNOPqrstuvwXYZ.ics"
        try KeychainHelper.saveFeedURL(url)
        let loaded = KeychainHelper.loadFeedURL()
        XCTAssertEqual(loaded, url, "文字化けなく保存・読み込みできること")
        XCTAssertEqual(loaded?.count, url.count, "文字数が変わっていないこと")
    }
}
