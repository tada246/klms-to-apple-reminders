import Foundation

@MainActor
class SyncCoordinator: ObservableObject {
    @Published var isSyncing      = false
    @Published var lastResult:    SyncResult?
    @Published var lastError:     String?
    @Published var isSessionExpired: Bool
    @Published var lastLoginDate: Date?

    /// セッション切れを検知したときに AppDelegate へ通知するコールバック
    var onSessionExpired: (() -> Void)?

    private let reminders = RemindersService()
    private var settings  = AppSettings()

    init() {
        lastLoginDate    = UserDefaults.standard.object(forKey: "lastLoginDate") as? Date
        // 起動時にトークンがなければログインが必要
        isSessionExpired = KeychainHelper.load() == nil
    }

    // MARK: - Public

    func sync() async {
        guard !isSyncing else { return }

        guard let token = KeychainHelper.load(), !token.isEmpty else {
            isSessionExpired = true
            lastError = "ログインが必要です。メニューから「再ログイン」を選択してください。"
            onSessionExpired?()
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

        await performSync(token: token, isRetry: false)
        isSyncing = false
    }

    /// ログイン成功後に呼ぶ。セッション状態を正常に戻す。
    func notifyLoginSuccess() {
        lastLoginDate    = UserDefaults.standard.object(forKey: "lastLoginDate") as? Date
        isSessionExpired = false
        lastError        = nil
    }

    // MARK: - Private

    private func performSync(token: String, isRetry: Bool) async {
        do {
            let client      = KLMSClient(token: token)
            let assignments = try await client.fetchAssignments(daysAhead: settings.daysAhead)
            let list        = try reminders.findOrCreateList(named: settings.listName)
            let existing    = await reminders.existingTitles(in: list)

            var added = 0, skipped = 0
            for assignment in assignments {
                if assignment.submitted || existing.contains(assignment.title) {
                    skipped += 1
                    continue
                }
                try reminders.addReminder(assignment, to: list)
                added += 1
            }

            lastResult       = SyncResult(added: added, skipped: skipped, timestamp: Date())
            isSessionExpired = false

        } catch KLMSError.invalidToken where !isRetry {
            // トークン期限切れ → Cookie でサイレントリフレッシュを試みる
            let refreshed = await CanvasAuthService.silentRefresh()
            if refreshed, let newToken = KeychainHelper.load() {
                await performSync(token: newToken, isRetry: true)
            } else {
                isSessionExpired = true
                lastError = "セッションが切れています。メニューから「再ログイン」してください。"
                onSessionExpired?()
            }

        } catch {
            lastError = error.localizedDescription
        }
    }
}
