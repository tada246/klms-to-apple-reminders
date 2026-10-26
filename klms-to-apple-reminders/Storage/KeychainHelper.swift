import Foundation
import Security

enum KeychainHelper {
    /// XCTest 実行中は別の service 名を使う。テストの setUp/tearDown は `deleteFeedURL()` を呼ぶので、
    /// 本番と同じ項目を使うと、開発機でテストを回すたびにユーザーのフィード URL を消してしまう。
    private static let service: String = {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            ? "klms-to-apple-reminders.tests"
            : "klms-to-apple-reminders"
    }()
    private static let feedURLAccount = "ics-feed-url"

    // MARK: - ICS Feed URL

    // Canvas カレンダーフィードの URL は秘密トークンを内包するため Keychain に保存する。

    static func saveFeedURL(_ url: String) throws {
        try saveItem(url, account: feedURLAccount)
    }

    static func loadFeedURL() -> String? {
        loadItem(account: feedURLAccount)
    }

    static func deleteFeedURL() {
        deleteItem(account: feedURLAccount)
    }

    // MARK: - Private helpers

    private static func saveItem(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  account,
        ]
        SecItemDelete(query as CFDictionary)

        let attributes: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  account,
            kSecValueData:    data,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private static func loadItem(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  account,
            kSecReturnData:   true,
            kSecMatchLimit:   kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteItem(account: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Error

    enum KeychainError: Error, LocalizedError {
        case saveFailed(OSStatus)
        var errorDescription: String? {
            switch self {
            case .saveFailed(let s): return "Keychain保存失敗 (OSStatus: \(s))"
            }
        }
    }
}
