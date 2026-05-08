import Foundation

@MainActor
class SyncCoordinator: ObservableObject {
    @Published var isSyncing = false
    @Published var lastResult: SyncResult?
    @Published var lastError: String?

    private let reminders = RemindersService()
    private var settings = AppSettings()

    func sync() async {
        guard !isSyncing else { return }

        guard let token = KeychainHelper.load(), !token.isEmpty else {
            lastError = "APIトークンが設定されていません。設定画面から入力してください。"
            return
        }

        isSyncing = true
        lastError = nil

        do {
            try await reminders.requestAccess()

            let client = KLMSClient(token: token)
            let assignments = try await client.fetchAssignments(daysAhead: settings.daysAhead)

            let list = try reminders.findOrCreateList(named: settings.listName)
            let existing = await reminders.existingTitles(in: list)

            var added = 0
            var skipped = 0

            for assignment in assignments {
                if assignment.submitted || existing.contains(assignment.title) {
                    skipped += 1
                    continue
                }
                try reminders.addReminder(assignment, to: list)
                added += 1
            }

            lastResult = SyncResult(added: added, skipped: skipped, timestamp: Date())
        } catch {
            lastError = error.localizedDescription
        }

        isSyncing = false
    }
}
