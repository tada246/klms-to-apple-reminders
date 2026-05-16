import XCTest
@testable import klms_to_apple_reminders

final class TokenValidatorTests: XCTestCase {

    // MARK: - 有効なトークン

    func testValidAlphanumeric() {
        XCTAssertTrue(TokenValidator.isValid("abc123"))
    }

    func testValidUppercase() {
        XCTAssertTrue(TokenValidator.isValid("ABC123"))
    }

    func testValidMixedCase() {
        XCTAssertTrue(TokenValidator.isValid("hY3wVfB9FfMLUU9nrytV3PmcU44wPXrw8QFULVKJWUkyQmMJ2vYnBPXDk2uKVNVv"))
    }

    func testValidOnlyLetters() {
        XCTAssertTrue(TokenValidator.isValid("abcdefgABCDEFG"))
    }

    func testValidOnlyNumbers() {
        XCTAssertTrue(TokenValidator.isValid("1234567890"))
    }

    // MARK: - 無効なトークン

    func testInvalidEmpty() {
        XCTAssertFalse(TokenValidator.isValid(""))
    }

    func testInvalidWithSpace() {
        XCTAssertFalse(TokenValidator.isValid("abc 123"), "スペースは不可")
    }

    func testInvalidWithLeadingSpace() {
        XCTAssertFalse(TokenValidator.isValid(" abc123"), "先頭スペースは不可")
    }

    func testInvalidWithTrailingSpace() {
        XCTAssertFalse(TokenValidator.isValid("abc123 "), "末尾スペースは不可")
    }

    func testInvalidWithHyphen() {
        XCTAssertFalse(TokenValidator.isValid("abc-123"), "ハイフンは不可")
    }

    func testInvalidWithUnderscore() {
        XCTAssertFalse(TokenValidator.isValid("abc_123"), "アンダースコアは不可")
    }

    func testInvalidWithNewline() {
        XCTAssertFalse(TokenValidator.isValid("abc\n123"), "改行は不可（コピペ時に混入しやすい）")
    }

    func testInvalidWithTab() {
        XCTAssertFalse(TokenValidator.isValid("abc\t123"), "タブは不可")
    }

    func testInvalidJapanese() {
        XCTAssertFalse(TokenValidator.isValid("abc日本語"), "日本語は不可")
    }
}
