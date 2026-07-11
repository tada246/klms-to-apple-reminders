import Foundation

// Canvas カレンダーフィード（.ics）を Keychain に保存された URL から直接取得する方式に移行したため、
// SSO ログイン・トークン失効・自動再ログインといった概念は不要になった。必要なのは URL の有無のみ。
@MainActor
class SyncCoordinator: ObservableObject {
    @Published var isSyncing      = false
    @Published var lastResult:    SyncResult?
    @Published var lastError:     String?
    @Published var isConfigured:  Bool

    /// フィード URL 未設定などで設定画面を開く必要があるときに AppDelegate へ通知するコールバック
    var onNeedsConfiguration: (() -> Void)?

    private let reminders = RemindersService()
    private var settings  = AppSettings()

    init() {
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

        isSyncing  = true
        lastError  = nil

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

    private func performSync(feedURL: URL) async {
        do {
            let client      = ICSFeedClient(feedURL: feedURL)
            let assignments = try await client.fetchAssignments(daysAhead: settings.daysAhead)
            let list        = try reminders.findOrCreateList(named: settings.listName)
            let existing    = await reminders.existingAssignmentIDs(in: list)

            var added = 0, skipped = 0
            for assignment in assignments {
                if let id = RemindersService.assignmentID(fromUID: assignment.uid),
                   existing.contains(id) {
                    skipped += 1
                    continue
                }
                try reminders.addReminder(assignment, to: list)
                added += 1
            }

            lastResult   = SyncResult(added: added, skipped: skipped, timestamp: Date())
            isConfigured = true

        } catch {
            lastError = error.localizedDescription
        }
    }
}
