# 設計書: イシュー #4 / #5 / #7 の解消

- 対象ブランチ: `feat/ics-feed-migration`（main より先行、未 push、PR なし）
- 作成日: 2026-10-26
- ステータス: **実装中**（方針確定: **ICS only**。Canvas API・トークンは導入しない → #4 は実装対象外、§4）

## 1. 要約

オープンなイシューは 3 件。

| # | 内容 | 根本原因 | 方針 |
|---|---|---|---|
| 7 | K-LMS の課題が更新されたらリマインダーも更新 | 同期が「課題 ID のリマインダーが既にあればスキップ」しかしない（`SyncCoordinator.swift:67-72`） | 同期ロジックを純粋関数 `SyncPlanner` に切り出し、「前回同期時の値」との 3-way 比較で追加／更新／維持を決める |
| 4 | 提出したら完了マークを付ける | .ics に提出状態が無い（`docs/ics-migration.md`）。.ics だけでは原理的に不可能 | **ICS only の方針により今回は実装しない。** 制約を記録し、イシューは開いたままにする（§4） |
| 5 | アプリアイコン | アイコン PNG は作業ツリーに存在しビルドにも入るが、未コミット。形状が macOS テンプレに非準拠 | 現行の絵柄を採用し、macOS テンプレ（角丸＋透明マージン）に載せる生成スクリプトを置く |

加えて、コードより先にドキュメントがずれているため整備する（§2.1）。

## 2. 現状分析

### 2.1 ドキュメント

| ファイル | 状態 | 問題 |
|---|---|---|
| `README.md` | **全面的に旧 SSO 方式** | 仕組み・認証フロー・機能表・ファイル構成・リセット手順・FAQ のすべてが WKWebView/トークン生成の話。存在しない `CanvasAuthService` / `KLMSClient` / `CanvasLoginWindow` / `TokenValidator` を列挙。Keychain 削除コマンドの account（`api-token` / `canvas-session`）と service 名も現行（`ics-feed-url` / `klms-to-apple-reminders`）と違う |
| `CLAUDE.md` | ほぼ最新 | 「notes 末尾に `[klms:<uid>]` マーカー」は `eaa7b0f` で廃止済み。現行は **リマインダーの `url` に埋まる課題数値 ID** で照合（`RemindersService.swift:51-70`）。テスト構成の記述も古い |
| `docs/ics-migration.md` | 一部陳腐化 | L27 に同じマーカー記述 |
| `ICSFeedClient.swift` ヘッダ | 最新 | 問題なし |

### 2.2 作業ツリー（未コミット）

- `TokenValidator.swift` 削除（参照ゼロ。削除して問題なし）
- `Assets.xcassets/AppIcon`（10 サイズ）＋ `project.yml` の `ASSETCATALOG_COMPILER_APPICON_NAME` ＋ `project.pbxproj`（Resources ビルドフェーズ追加）。ビルド成果物に `AppIcon.icns` / `Assets.car` が入ることを確認済み → #5 の配線は完了している
- `build/`（Release 成果物、未 ignore）、`check_token.py`・`.env`（SSO 時代の残骸。`.env` は gitignore 済みで中身は読んでいない）、`xcshareddata/`
- ベースライン: `xcodebuild test` で **13 テスト全通過**（Keychain 5 + ID 抽出 8）。**ICS パーサのテストは 0 件**

### 2.3 コード観察（今回の変更に効くもの）

1. **差分検知が存在しない**: `performSync` は ID の有無でスキップするだけ（#7 の直接原因）。
2. **期間フィルタが取得段階に埋まっている**（`ICSFeedClient.swift:75-92`）: 締切が窓の外へ動いた課題は「見えなくなる」ので、更新も検知できない。
3. **HTTP キャッシュ**: `URLSession.shared.data(from:)` は既定のキャッシュポリシー。フィードがキャッシュ可能なヘッダを返すと、更新が見えない可能性がある。
4. **1 件の失敗で全体が中断**: `try reminders.addReminder` が throw すると catch に飛び、それまでの `added` 集計も捨てられる（`SyncCoordinator.swift:73-82`）。
5. **テスト不能な構造**: `ICSParser` は `private enum`、同期ループは `EKEventStore` 直結。
6. **既知の挙動（今回は変更しない）**: ユーザーが削除したリマインダーは次回同期で復活する。完了済みは復活しない。

### 2.4 未検証の前提

Keio の Canvas に実アクセスできないため、ICS の実フィード形式は `ICSFeedClient.swift` ヘッダのサンプルに依拠する。本件で追加の外部 API 前提は無い。

## 3. #7 設計: 課題更新のリマインダー反映

### 3.1 構成

```
ICSFeedClient ──► [Assignment]（期間フィルタ前の全件）
RemindersService.fetchRecords(in:) ──► [ReminderRecord]（EventKit 非依存の値型）
SnapshotStore ──► [assignmentID: SyncedSnapshot]
                    │
                    ▼
        SyncPlanner.plan(...)  ← 純粋関数。ここに全ロジック
                    │
                    ▼
              [SyncAction]  = add / update(fields) / seed
                    │
                    ▼
   RemindersService.apply(actions)  ← EventKit を触るのはここだけ（commit は 1 回）
```

- `SyncPlanner` は EventKit に依存しないので XCTest で網羅できる。EventKit 層は薄く保つ。
- 期間フィルタ（`now-1日 〜 now+daysAhead日`）は **新規追加の判定にだけ**適用する。既存リマインダーがある課題は窓外でも更新対象。`ICSFeedClient` は全課題を返し、窓は `SyncPlanner` 側で適用する。
- `URLRequest` は `cachePolicy: .reloadIgnoringLocalCacheData`、`timeoutInterval: 30` にする。

### 3.2 反映対象と照合キー

- 照合キーは従来どおり課題数値 ID（UID と `reminder.url` の両方から抽出）。
- 反映する項目は **タイトル / 締切 / notes（コース名）**。URL は ID から決まるため更新不要。
- 同じ ID のリマインダーが複数あれば、未完了のうち先頭を対象にする。

### 3.3 3-way 比較（ユーザー編集を守る）

各項目で「Canvas の現在値 F」「リマインダーの現在値 R」「前回同期で記録した値 S」を比べる。

| 状況 | タイトル / notes | 締切 |
|---|---|---|
| F == R | 何もしない（S := F） | 同左 |
| S あり・F == S・R ≠ S（ユーザーが編集、Canvas は不変） | 維持 | 維持 |
| S あり・F ≠ S・R == S（Canvas だけ変更） | **F で更新** | **F で更新** |
| S あり・F ≠ S・R ≠ S（両方変更） | **R を維持**（ユーザー優先、S := F） | **F で更新**（公式締切の変更を見落とす方が被害が大きい） |
| S なし（この機能の導入前に作ったリマインダー） | R を維持（S := F） | **F で更新**（一度だけ。以後は保護対象） |

- **完了済みリマインダーは一切変更しない。**
- 終日⇔時刻付きの切り替えも「締切の更新」として扱う（`dueDateComponents` を作り直す）。
- 比較は `DateComponents` ではなく正規化した文字列（`2026-07-15T23:59` / `2026-07-15`）で行い、タイムゾーンや秒の揺れを排除する。

### 3.4 データモデル

```swift
struct ReminderRecord {            // EKReminder の値スナップショット
    let identifier: String         // calendarItemIdentifier
    let assignmentID: String
    let title: String
    let dueKey: String?            // 正規化済み
    let notes: String?
    let isCompleted: Bool
}

struct SyncedSnapshot: Codable {   // 前回同期で「Canvas 由来として書いた/確認した」値
    var title: String
    var dueKey: String?
    var notes: String?
}

enum SyncAction {
    case add(Assignment)
    case update(recordID: String, assignmentID: String, changes: FieldChanges)
    case seed(assignmentID: String, SyncedSnapshot)   // スナップショットだけ更新
}
```

- `SnapshotStore` はプロトコル。実装は `UserDefaults`（JSON）。テストはインメモリ実装を注入する。
- スナップショットは「リマインダーも Canvas にも存在しない ID」を同期のたびに掃除する。
- **採用しなかった案**: notes や URL フラグメントに指紋を埋める（ユーザーの目に触れる／URL が汚れる。`eaa7b0f` で notes マーカーを廃止した方針に反する）。

### 3.5 Canvas から消えた課題

**放置する（何もしない）。** フィードの収録範囲は有限なので「フィードに無い＝Canvas で削除された」とは断定できず、自動削除・自動完了は破壊的になりうる。

### 3.6 結果表示

`SyncResult` に `updated` / `failed` を追加し、メニューの表示は「追加2・更新1・変更なし10」。1 件の失敗では全体を止めず、失敗は集計して警告として表示する。

## 4. #4: ICS only 方針での扱い

**今回は実装しない。**

- .ics の VEVENT に提出状態は無い。提出済みかどうかは Canvas API（`planner/items` の `submissions` 等）でしか取れず、API にはアクセストークンが要る。
- ICS 移行（`docs/ics-migration.md`）は「SSO セッション失効による再ログイン」を無くすために認証コードを丸ごと捨てた。ICS only はその方針の維持であり、トークン保存・API クライアントは持ち込まない。
- 現状で既にできること: **リマインダーを手で完了にすれば、再同期で復活しない**（`existingAssignmentIDs` が完了済みも走査するため）。
- イシューの扱い: クローズせず開いたままにする。コメント追記やラベル付けは外部への書き込みなので、完了後に相談する。
- 将来やる場合の参考: 任意の Canvas アクセストークン＋`planner/items`。旧実装（`git show a84fce8:klms-to-apple-reminders/Services/KLMSClient.swift`）にページング（`Link` ヘッダ）と `submissions` の Bool／オブジェクト多態デコード（`93c54ef` で踏んだ罠）がある。クイズは planner の ID が UID と一致しない可能性があり、実機確認が必要。

## 5. #5 設計: アプリアイコン

- 現状: 1024px の絵柄（グレーのカプセル 3 本が白地いっぱい）が 10 サイズに書き出され、ビルドにも入っている。ただし**フルブリードの正方形**で、macOS の標準アイコン（角丸＋周囲の透明マージン）と並べると大きく平らに見える。
- 方針: 絵柄は変えず、`design/icon/AppIcon-source.png` に原画を保存し、`scripts/make-app-icon.swift`（CoreGraphics）で 824px の角丸（macOS 比率）＋透明マージン＋影を作って 10 サイズを `AppIcon.appiconset` に出力する。再生成可能にしてあるので、Figma で絵柄を作り直したら原画を差し替えて再実行するだけでよい。
- 検証: 生成物を目視（画像を開いて確認）、Release ビルドの `AppIcon.icns` の存在、サイズ整合を確認する。
- メニューバーのアイコンは SF Symbol `checklist` のまま（イシューの対象外）。

## 6. ドキュメント整備

- `README.md`: ICS 方式に全面書き換え（仕組み、セットアップ、フィード URL の取得手順、機能表、ファイル構成、現行のリセット手順、FAQ）。FAQ に「提出済みは自動で完了にならない。手で完了にすれば復活しない」を明記。
- `CLAUDE.md`: 重複回避の記述を「URL の課題 ID」に訂正、`SyncPlanner`／スナップショットを追記、テスト構成を更新。
- `docs/ics-migration.md`: マーカー記述に訂正注記。
- 本書: 実装完了後にステータスを「実装済み」に更新し、検証結果を追記。

## 7. テスト・検証計画

### 7.1 単体テスト（目標: 既存 13 → 50 前後）

| 対象 | 主なケース |
|---|---|
| `ICSParser`（`private` → `internal` に変更） | 行アンフォールディング、UTC／終日／TZID の 3 形式、エスケープ解除、`splitTitleAndCourse`（入れ子の `[]`、`任意課題[慶應義塾史展示館]`）、`assignmentPageURL`、課題以外の UID の除外 |
| `ICSFeedClient`（`URLProtocol` スタブ） | 200 / 非 200 / 非 UTF-8、キャッシュポリシー、全件返却（窓フィルタは Planner 側） |
| `SyncPlanner` | 新規追加、窓外は追加しない・既存は窓外でも更新、変更なし、§3.3 の全マス、完了済み不変、S なし（旧作成分）、重複 ID、終日⇔時刻付き切替 |
| 正規化（dueKey） | 終日・時刻付き・タイムゾーン境界 |
| `SnapshotStore` | 保存・読込・掃除・破損時のフォールバック |

### 7.2 ビルド・動作確認（自走）

1. `xcodegen generate` → Debug `xcodebuild test`（全通過）
2. Release ビルド → 起動スモーク（プロセス生存、クラッシュログなし）。可能ならスクリーンショットでアイコンを確認
3. EventKit 実機テストは `XCTSkip` 付き（リマインダー権限が無ければスキップ。専用の一時リストを作って後始末）
4. 最後に CLAUDE.md の手順どおり `/Applications` へ差し替え

## 8. 作業順序とコミット

すべてローカルコミット（push・PR はしない）。1 フェーズ 1 コミット、各コミット時点でテスト全通過。

| フェーズ | 内容 | コミット |
|---|---|---|
| P0 | 作業ツリー整理（`TokenValidator` 削除、`build/` を `.gitignore`、アセット＋`project.yml`＋pbxproj の取り込み、`check_token.py` 削除） | `chore:` |
| P1 | README／CLAUDE.md／ics-migration の訂正（§6） | `docs:` |
| P2 | テスト可能化（`ICSParser` を internal、パーサ・クライアントのテスト追加、キャッシュポリシー修正） | `test:` |
| P3 | #7 実装（`SyncPlanner`／`SnapshotStore`／`ReminderRecord`／`RemindersService` 分離／`SyncResult` 拡張） | `feat: … (Closes #7)` |
| P4 | #5 実装（原画保存、生成スクリプト、アイコン再生成） | `feat: … (Closes #5)` |
| P5 | 最終検証（§7.2）、本書のステータス更新 | `docs:` |

## 9. リスクと対応

| リスク | 対応 |
|---|---|
| 導入初回に旧作成分の締切が一括更新される | §3.3 の「S なし」行どおり、締切のみ一度だけ Canvas 値で更新。タイトル・notes はユーザー値を保持。結果表示に「更新N」として出る |
| iCloud 同期でリマインダーが別端末から編集される | 値比較（時刻ではなく値）なので、どの端末の編集でも「ユーザー編集」として扱われる |
| `UserDefaults` のスナップショット破損 | デコード失敗時は空として扱う（＝「S なし」行の挙動に落ちる。壊れない側へ倒す） |
| 実フィードの形式が想定とずれる | 既存の ICS パーサ仕様（ヘッダコメント）を単体テストで固定し、ずれたら差分で気付けるようにする |

## 10. 対象外（今回やらない）

- **#4（提出で自動完了）**: ICS only のため（§4）
- 削除したリマインダーの復活防止（スナップショットがあるので将来は可能）
- Canvas から消えた課題の自動削除・自動完了（§3.5）
- メニューバーアイコンの変更
- PR #6（旧 SSO 方式）のクローズ、push、新規 PR 作成、イシューへのコメント

## 11. 確定事項

1. **ICS only**（Canvas API・トークンは導入しない）。#4 は実装せず開いたまま。
2. Canvas から消えた課題は放置。
3. アイコンは現行の絵柄を採用し macOS テンプレに載せる。
4. `check_token.py` は削除（`.env` は触らない。中身も読まない）。
5. コミットはローカルのみ。push／PR／PR #6／イシューコメントの扱いは完了後に相談。
6. `/Applications` への差し替えは最後に実施。
