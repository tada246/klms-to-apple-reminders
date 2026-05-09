import Foundation

enum TokenValidator {
    /// 英大小文字・数字のみ許可（スペース・記号は不可）
    static func isValid(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        return token.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    static var invalidMessage: String {
        "英数字（A-Z, a-z, 0-9）のみ使用できます。スペースや記号が含まれていないか確認してください。"
    }
}
