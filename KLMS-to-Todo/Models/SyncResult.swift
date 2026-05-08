import Foundation

struct SyncResult {
    let added: Int
    let skipped: Int
    let timestamp: Date

    var summary: String {
        "\(added)件追加、\(skipped)件スキップ"
    }

    var formattedTime: String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        f.locale = Locale(identifier: "ja_JP")
        return f.string(from: timestamp)
    }
}
