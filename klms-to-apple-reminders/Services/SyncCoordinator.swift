import Foundation

// Canvas カレンダーフィード（.ics）を Keychain に保存された URL から直接取得する方式に移行したため、
// SSO ログイン・トークン失効・自動再ログインといった概念は不要になった。必要なのは URL の有無のみ。
@MainActor
class SyncCoordinator: ObservableObject {
    @Published var isSyncing      = false
    @Published var lastResult:    SyncResult?
    @Published var lastError:     String?
    /// 同期は完了したが、一部の課題を反映できなかったなどの注意（アイコンはエラー表示にしない）。
    @Published var lastWarning:   String?
    @Published var isConfigured:  Bool

    /// フィード URL 未設定などで設定画面を開く必要があるときに AppDelegate へ通知するコールバック
    var onNeedsConfiguration: (() -> Void)?

    private let reminders = RemindersService()
    private var settings  = AppSettings()
    private let snapshotStore: SnapshotStore

    init(snapshotStore: SnapshotStore = UserDefaultsSnapshotStore()) {
        self.snapshotStore = snapshotStore
        isConfigured = KeychainHelper.loadFeedURL() != nil
    }

    // MARK: - Public

    func sync() async {
        guard !isSyncing else { return }

        guard let feedURLString = KeychainHelper.loadFeedURL(),
              let feedURL = URL(string: feedURLString) else {
            isConfigured = false
            lastError = "フィード URL が未設定です。設定から貼り付けてください。"
            onNeedsConfiguration?()
            return
        }

        isSyncing   = true
        lastError   = nil
        lastWarning = nil

        // リマインダーアクセスを先に確認
        do {
            try await reminders.requestAccess()
        } catch {
            lastError = error.localizedDescription
            isSyncing = false
            return
        }

        await performSync(feedURL: feedURL)
        isSyncing = false
    }

    /// フィード URL 設定完了後に呼ぶ。設定済み状態に戻す。
    func notifyConfigured() {
        isConfigured = true
        lastError    = nil
    }

    // MARK: - Private

    /// Canvas の課題と既存リマインダーを突き合わせ、追加と更新を行う（計画は `SyncPlanner`）。
    private func performSync(feedURL: URL) async {
        do {
            let client      = ICSFeedClient(feedURL: feedURL)
            let assignments = try await client.fetchAllAssignments()
            let list        = try reminders.findOrCreateList(named: settings.listName)

            guard let records = await reminders.fetchRecords(in: list) else {
                throw RemindersError.fetchFailed
            }

            let previous = snapshotStore.load()
            let window   = ICSFeedClient.window(daysAhead: settings.daysAhead, now: Date())
            let plan     = SyncPlanner.plan(feed: assignments, records: records, snapshots: previous, window: window)
            let outcome  = reminders.apply(plan, to: list)

            snapshotStore.save(
                SyncPlanner.finalSnapshots(plan: plan, previous: previous, failedIDs: outcome.failedIDs)
            )

            lastResult = SyncResult(
                added:     outcome.added,
                updated:   outcome.updated,
                unchanged: plan.unchanged,
                failed:    outcome.failedIDs.count,
                timestamp: Date()
            )
            lastWarning  = Self.warning(plan: plan, outcome: outcome)
            isConfigured = true

        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func warning(plan: SyncPlan, outcome: ApplyOutcome) -> String? {
        var lines: [String] = []
        if plan.skippedWithoutID > 0 {
            lines.append("課題 ID を取り出せない \(plan.skippedWithoutID) 件をスキップしました。")
        }
        if let first = outcome.failureMessages.first {
            lines.append("\(outcome.failureMessages.count) 件を反映できませんでした（\(first)）")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
