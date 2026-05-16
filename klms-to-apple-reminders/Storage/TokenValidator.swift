import Foundation

enum TokenValidator {
    /// 英大小文字・数字のみ許可（スペース・記号は不可）
    static func isValid(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        // ASCII英数字のみ許可（Unicode文字・日本語・記号・スペースは不可）
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return token.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static var invalidMessage: String {
        "英数字（A-Z, a-z, 0-9）のみ使用できます。スペースや記号が含まれていないか確認してください。"
    }
}
