import XCTest
@testable import klms_to_apple_reminders

final class KeychainHelperTests: XCTestCase {

    override func setUp() {
        super.setUp()
        KeychainHelper.delete()
    }

    override func tearDown() {
        KeychainHelper.delete()
        super.tearDown()
    }

    // MARK: - 保存・読み込み

    func testSaveAndLoad() throws {
        let token = "abc123XYZ"
        try KeychainHelper.save(token)
        let loaded = KeychainHelper.load()
        XCTAssertEqual(loaded, token, "保存したトークンが正しく読み込めること")
    }

    func testLoadReturnsNilWhenEmpty() {
        let loaded = KeychainHelper.load()
        XCTAssertNil(loaded, "トークンが未保存の場合 nil を返すこと")
    }

    func testOverwrite() throws {
        try KeychainHelper.save("firstToken123")
        try KeychainHelper.save("secondToken456")
        let loaded = KeychainHelper.load()
        XCTAssertEqual(loaded, "secondToken456", "上書き保存が正しく動作すること")
    }

    func testDelete() throws {
        try KeychainHelper.save("abc123")
        KeychainHelper.delete()
        let loaded = KeychainHelper.load()
        XCTAssertNil(loaded, "削除後は nil を返すこと")
    }

    func testSaveLongToken() throws {
        // 実際のCanvas APIトークンは64文字
        let longToken = "hY3wVfB9FfMLUU9nrytV3PmcU44wPXrw8QFULVKJWUkyQmMJ2vYnBPXDk2uKVNVv"
        XCTAssertEqual(longToken.count, 64)
        try KeychainHelper.save(longToken)
        let loaded = KeychainHelper.load()
        XCTAssertEqual(loaded, longToken, "64文字のトークンが正確に保存・読み込みできること")
    }

    func testTokenNotCorrupted() throws {
        // 大文字・小文字・数字が混在するトークンで文字化けしないこと
        let token = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789AB"
        try KeychainHelper.save(token)
        let loaded = KeychainHelper.load()
        XCTAssertEqual(loaded, token, "文字化けなく保存・読み込みできること")
        XCTAssertEqual(loaded?.count, token.count, "文字数が変わっていないこと")
    }
}
