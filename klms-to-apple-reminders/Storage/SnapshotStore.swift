import Foundation

/// 前回同期で記録した Canvas の値（課題 ID → `SyncedFields`）の保存先。
/// ユーザーがリマインダーを編集したかどうかの判定（3-way 比較）に使う。
protocol SnapshotStore {
    func load() -> [String: SyncedFields]
    func save(_ snapshots: [String: SyncedFields])
}

/// UserDefaults に JSON で保存する。壊れていたら空として扱う
/// （＝「この機能の導入前に作られたリマインダー」と同じ、ユーザー編集を守る側の挙動になる）。
struct UserDefaultsSnapshotStore: SnapshotStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "syncSnapshots") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [String: SyncedFields] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: SyncedFields].self, from: data) else {
            return [:]
        }
        return decoded
    }

    func save(_ snapshots: [String: SyncedFields]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        defaults.set(data, forKey: key)
    }
}
