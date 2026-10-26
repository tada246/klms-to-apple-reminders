import Foundation

struct SyncResult {
    let added: Int
    let updated: Int
    let unchanged: Int
    let failed: Int
    let timestamp: Date

    var summary: String {
        var text = "追加\(added)・更新\(updated)・変更なし\(unchanged)"
        if failed > 0 { text += "・失敗\(failed)" }
        return text
    }

    var formattedTime: String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        f.locale = Locale(identifier: "ja_JP")
        return f.string(from: timestamp)
    }
}
