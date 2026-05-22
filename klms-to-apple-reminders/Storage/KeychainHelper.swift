import Foundation
import Security

enum KeychainHelper {
    private static let service = "io.github.tada246.klms-to-apple-reminders"
    private static let tokenAccount  = "api-token"
    private static let cookieAccount = "canvas-session"

    // MARK: - API Token

    static func save(_ token: String) throws {
        try saveItem(token, account: tokenAccount)
    }

    static func load() -> String? {
        loadItem(account: tokenAccount)
    }

    static func delete() {
        deleteItem(account: tokenAccount)
    }

    // MARK: - Canvas Session Cookie

    static func saveCookie(_ cookieHeader: String) throws {
        try saveItem(cookieHeader, account: cookieAccount)
    }

    static func loadCookie() -> String? {
        loadItem(account: cookieAccount)
    }

    static func deleteCookie() {
        deleteItem(account: cookieAccount)
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
