import Foundation

/// Canvas（.ics）の課題と既存リマインダーを突き合わせ、「何を追加し、何を更新するか」を決める純粋関数群。
/// EventKit に触れないので単体テストで全ケースを検証できる。
///
/// 各項目で「Canvas の現在値 F」「リマインダーの現在値 R」「前回同期で記録した Canvas の値 S」を比べる。
///
/// | 状況                                 | タイトル / notes      | 締切                     |
/// |--------------------------------------|-----------------------|--------------------------|
/// | F == R                               | 何もしない            | 同左                     |
/// | S あり・F == S（Canvas 不変）        | 維持（ユーザー編集）  | 維持                     |
/// | S あり・F != S・R == S（未編集）     | F で更新              | F で更新                 |
/// | S あり・F != S・R != S（両方変更）   | R を維持              | F で更新（公式締切優先） |
/// | S なし（この機能の導入前の作成分）   | R を維持              | F で更新（一度だけ）     |
///
/// 同期後の S は常に F（「最後に見た Canvas の値」）になる。完了済みリマインダーは一切変更しない。
enum SyncPlanner {

    static func plan(
        feed: [Assignment],
        records: [ReminderRecord],
        snapshots: [String: SyncedFields],
        window: ClosedRange<Date>
    ) -> SyncPlan {
        var plan = SyncPlan()

        // 課題 ID ごとに対象リマインダーを決める。同じ ID が複数あれば未完了を優先する。
        var target: [String: ReminderRecord] = [:]
        for record in records {
            if let current = target[record.assignmentID] {
                if current.isCompleted && !record.isCompleted { target[record.assignmentID] = record }
            } else {
                target[record.assignmentID] = record
            }
        }

        var seenFeedIDs = Set<String>()
        for assignment in feed {
            guard let id = RemindersService.assignmentID(fromUID: assignment.uid) else {
                plan.skippedWithoutID += 1
                continue
            }
            // フィード内で同じ ID が重複していたら最初のものを採用する。
            guard seenFeedIDs.insert(id).inserted else { continue }

            let inWindow = assignment.dueAt.map { window.contains($0) } ?? false
            let feedFields = SyncedFields(assignment: assignment)

            guard let record = target[id] else {
                // リマインダーが無い課題は、期間内のものだけ新規追加する。
                if inWindow {
                    plan.adds.append(assignment)
                    plan.snapshots[id] = feedFields
                }
                continue
            }

            if record.isCompleted {
                // 完了済みは触らない（復活もさせない）。スナップショットだけ引き継ぐ。
                if inWindow { plan.unchanged += 1 }
                if let previous = snapshots[id] { plan.snapshots[id] = previous }
                continue
            }

            let fields = changedFields(feed: feedFields, reminder: SyncedFields(record: record), snapshot: snapshots[id])
            if fields.isEmpty {
                if inWindow { plan.unchanged += 1 }
            } else {
                plan.updates.append(
                    ReminderUpdate(recordID: record.identifier, assignmentID: id, assignment: assignment, fields: fields)
                )
            }
            plan.snapshots[id] = feedFields
        }

        // リマインダーはあるがフィードに無い課題（期間外へ消えた等）: 値を比べられないので前回の記録を残す。
        // リマインダーが無い ID のスナップショットは引き継がない（ここで掃除される）。
        for (id, _) in target where !seenFeedIDs.contains(id) {
            if let previous = snapshots[id] { plan.snapshots[id] = previous }
        }

        return plan
    }

    /// 適用に失敗した ID は前回のスナップショットに戻す（次回の同期でやり直せるようにする）。
    static func finalSnapshots(
        plan: SyncPlan,
        previous: [String: SyncedFields],
        failedIDs: Set<String>
    ) -> [String: SyncedFields] {
        var result: [String: SyncedFields] = [:]
        for (id, fields) in plan.snapshots {
            if failedIDs.contains(id) {
                if let old = previous[id] { result[id] = old }
            } else {
                result[id] = fields
            }
        }
        return result
    }

    // MARK: - Private

    private static func changedFields(
        feed F: SyncedFields,
        reminder R: SyncedFields,
        snapshot S: SyncedFields?
    ) -> Set<SyncField> {
        var fields = Set<SyncField>()

        // タイトル・notes: Canvas だけが変わったときに限って更新する。ユーザーの編集は常に優先。
        // S が無いとユーザー編集か Canvas 変更か判別できないので、R を維持する。
        if let S {
            if F.title != R.title, F.title != S.title, R.title == S.title { fields.insert(.title) }
            if F.notes != R.notes, F.notes != S.notes, R.notes == S.notes { fields.insert(.notes) }
        }

        // 締切: Canvas が変わったら、ユーザー編集があっても Canvas を優先する（公式締切の変更の見落としを避ける）。
        // S が無い場合は、導入前に作ったリマインダーの古い締切を直すため一度だけ Canvas に合わせる。
        // Canvas に締切が無いときに既存の締切を消すことはしない。
        if let feedDue = F.dueKey, feedDue != R.dueKey {
            if let S {
                if feedDue != S.dueKey { fields.insert(.due) }
            } else {
                fields.insert(.due)
            }
        }

        return fields
    }
}
