# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# プロジェクトファイル再生成（Swift ファイルを追加・削除した後は必須）
xcodegen generate

# Debug ビルド
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project klms-to-apple-reminders.xcodeproj \
  -scheme klms-to-apple-reminders -configuration Debug \
  -derivedDataPath /tmp/klms-build build

# Release ビルド → /Applications にコピー
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project klms-to-apple-reminders.xcodeproj \
  -scheme klms-to-apple-reminders -configuration Release \
  -derivedDataPath /tmp/klms-build build
cp -R /tmp/klms-build/Build/Products/Release/klms-to-apple-reminders.app /Applications/

# テスト実行（全テスト）
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project klms-to-apple-reminders.xcodeproj \
  -scheme klms-to-apple-reminders -configuration Debug \
  -derivedDataPath /tmp/klms-build test

# 単一テストクラスを実行
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project klms-to-apple-reminders.xcodeproj \
  -scheme klms-to-apple-reminders -configuration Debug \
  -derivedDataPath /tmp/klms-build \
  -only-testing:klms-to-apple-remindersTests/KeychainHelperTests test
```

エラーだけ見たい場合は末尾に `2>&1 | grep -E "error:|BUILD"` を追加する。

## プロジェクト構成

`project.yml`（xcodegen）でプロジェクトを管理している。Swift ファイルはディレクトリスキャンで自動収集されるため、`.xcodeproj` を直接編集しない。新規ファイルを追加したら `xcodegen generate` を実行すること。

**アプリアイコン**: `Assets.xcassets/AppIcon.appiconset` の PNG は手で編集しない。原画 `design/icon/AppIcon-source.png`（1024×1024）から `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/make-app-icon.swift` で生成する（`swiftly` の swift には CoreGraphics が無いので Xcode の swift を使う）。

**依存フレームワーク**: EventKit / AppKit / SwiftUI（標準）。WebKit 依存は撤去済み。サンドボックスは無効（`entitlements` で `app-sandbox = false`）。

## アーキテクチャ概要

### 全体のデータフロー

```
Canvas カレンダーフィード (.ics, 秘密トークン内包)
    ↓ ICSFeedClient（Bearer 不要の HTTP GET + 最小 ICS パーサ）
SyncCoordinator（@MainActor, ObservableObject）
    ↓ RemindersService（EventKit, 課題 ID による重複回避）
Apple リマインダー
```

- **`KLMSToAppleRemindersApp`**: `@main`。WindowGroup を使わず、`AppDelegate` を `@NSApplicationDelegateAdaptor` で使うメニューバー専用構成。
- **`AppDelegate`**: 全ウィンドウのライフサイクル管理（オンボーディング・設定）。`SyncCoordinator` と `SchedulerService` のオーナー。
- **`SyncCoordinator`**: `@MainActor` の `ObservableObject`。同期状態（`isSyncing`, `lastError`, `isConfigured`）を持ち、UI が購読する。
- **`StatusItemManager`**: `coordinator.objectWillChange` を購読してメニューバーアイコンを更新。

### データ取得フロー（最重要）

以前は WKWebView で Keio SSO ログイン → Cookie からトークン動的生成 → Bearer で `planner/items` を叩いていたが、SSO セッションが数時間で失効し再ログインが頻発した。現在は **Canvas カレンダーフィード（.ics）URL** に一本化している（移行の経緯は `docs/ics-migration.md`）。

```
初回設定:
  ユーザーが Canvas のカレンダーフィード URL を設定画面に貼り付け
      → KeychainHelper.saveFeedURL()（account: "ics-feed-url"）
  ※ フィード URL は SSO と独立して長期間有効。ログインは不要。

同期（SyncCoordinator.sync → performSync）:
  KeychainHelper.loadFeedURL()
      → ICSFeedClient(feedURL:).fetchAllAssignments()   ← 期間フィルタなしの全件
          → .ics を HTTP GET（Bearer 不要・HTTP キャッシュ無効）
          → 最小 ICS パーサで VEVENT を抽出
          → UID が "event-assignment-" で始まり DTSTART があるものだけを Assignment 化
      → RemindersService.fetchRecords(in:) で既存リマインダーを値型で取得（完了済みも含む。失敗は nil）
      → SnapshotStore.load() で前回同期時の Canvas 値を取得
      → SyncPlanner.plan(...)  ← 追加／更新／維持を決める純粋関数（EventKit 非依存）
      → RemindersService.apply(plan)  ← 1 件ずつ commit。失敗しても他の課題は続行
      → SyncPlanner.finalSnapshots(...) を SnapshotStore.save()（失敗した ID は前回値に戻す）
  URL 未設定なら isConfigured=false、onNeedsConfiguration → AppDelegate が設定を開く
```

**ICS パーサ**（`ICSFeedClient.swift` 内 `ICSParser`）: 行アンフォールディング、`BEGIN/END:VEVENT` 抽出、`UID`/`SUMMARY`/`DTSTART`/`URL` 取得、ICS エスケープ解除、DTSTART の3形式（末尾 Z の UTC / `VALUE=DATE` 終日 / `TZID` 付き）に対応。SUMMARY 末尾の `[コース名]` を分離。前提とする実 VEVENT サンプルはファイル冒頭コメント参照。

**.ics の制約と対処**: フィードには提出済みフラグが無い（提出で自動完了にはできない。ICS only 方針のため Canvas API・トークンは使わない）。そのため重複回避は Canvas API の `submitted` ではなく **課題の数値 ID** で行う。UID（`event-assignment-1269269`）とリマインダーの `url`（`…/assignments/1269269`）の両方から同じ ID を正規表現で取り出して突き合わせる（`RemindersService.assignmentID(...)`）。notes にマーカーは埋めない（`eaa7b0f` で廃止）。既存リマインダーは **完了済みを含めて** 走査する。完了課題が再同期で復活しないようにするため。

### 課題の更新反映（イシュー #7）

Canvas 側で課題が変わったら、対応するリマインダーのタイトル／締切／notes（コース名）を更新する。判定は `Services/SyncPlanner.swift`（表は同ファイル冒頭と `docs/design-issues-4-5-7.md` §3.3）。

- 各項目で **F（Canvas の現在値）/ R（リマインダーの現在値）/ S（前回同期で記録した Canvas の値）** を比べる。S は `UserDefaultsSnapshotStore`（UserDefaults の JSON, key `syncSnapshots`）に課題 ID 単位で保存し、同期後は常に F に進める。
- ユーザーの編集を守る: タイトル／notes は「Canvas だけが変わり、R == S」のときだけ更新。**締切だけは Canvas が変わればユーザー編集があっても Canvas を優先**（公式締切の見落とし防止）。S が無い（機能導入前に作成）リマインダーは、締切のみ一度だけ Canvas に合わせ、タイトル／notes は触らない。
- **完了済みリマインダーは一切変更しない**（復活もさせない）。
- 締切の比較は `DueKey`（端末 TZ のグレゴリオ暦で `2026-07-15T23:59` / 終日は `2026-07-15`）。`DateComponents` を直接比べない。
- 期間フィルタ（`ICSFeedClient.window`）は **新規追加の判定にだけ**使う。既存リマインダーがある課題は期間外でも更新する。
- Canvas から消えた課題のリマインダーは放置（フィードの収録範囲は有限で、削除と断定できないため）。
- 提出済みでの自動完了（#4）は ICS only のため対象外。

### Keychain のキー構造

| account | 内容 |
|---|---|
| `"ics-feed-url"` | Canvas カレンダーフィード URL（秘密トークンを内包） |

### 設定状態と UI の対応

| `isConfigured` | アイコン | メニュー |
|---|---|---|
| true, syncing | `arrow.clockwise` | 通常 |
| true, error | `exclamationmark.circle` | 通常 |
| true, 正常 | `checklist` | 通常 |
| **false（URL 未設定）** | **`exclamationmark.circle`** | **「フィード URL が未設定です」表示＋設定へ誘導** |

### 並行処理の注意点

- `SyncCoordinator` と `RemindersService` は `@MainActor`。`RemindersService` の ID 抽出用純粋関数（`assignmentID(in:)` / `assignmentID(fromUID:)` / `assignmentID(from:)`）は `nonisolated static`。
- `AppDelegate` のクロージャから `coordinator`（MainActor）を呼ぶときは `Task { @MainActor [weak self] in ... }` が必要。

### スケジューラ

`SchedulerService` は `Timer` ベース（`RunLoop.main`）。`SyncInterval` は `hourly / daily / weekly` の3種。`AppDelegate.openSettings` のコールバックでスケジュールを再設定する。

## 既知の注意点

- **`ICSFeedClient.swift`** のヘッダコメントに Canvas フィードの実 VEVENT サンプルを記載。将来フォーマットが変わったら実出力と diff してパーサを調整する。
- **重複回避は課題 ID ベース**。リマインダーの `url` に課題 ID が入っていることが前提。ユーザーが手で作った（課題 URL を持たない）リマインダーは dedup 対象外。
- **`KeychainHelperTests`** は `.setUp`/`.tearDown` で `KeychainHelper.deleteFeedURL()` を呼ぶ。XCTest 実行中（環境変数 `XCTestConfigurationFilePath` あり）は Keychain の service 名が `klms-to-apple-reminders.tests` に切り替わるので、本番のフィード URL は消えない。同じ判定で `AppDelegate.applicationDidFinishLaunching` も何もせず戻る（テストホストがログイン項目に登録されたり設定ウィンドウが開いたりするのを防ぐため）。`RemindersServiceTests` は課題 ID 抽出（純粋関数）のみを検証し、EventKit には触れない。
- ユーザーが削除したリマインダーは次回同期で復活する（完了済みは復活しない）。
- 課題判定は UID プレフィックス `event-assignment-`（クイズも Canvas ではこの系）。他の Canvas インスタンスでは UID 形式が異なる場合がある。
- 期間フィルタは `now-1日` 〜 `now+daysAhead日`（新規追加のみ）。過去1日を含めるのは締切直後の未提出課題を取りこぼさないため。
- `ICSParser` の日時は `en_US_POSIX` + グレゴリオ暦で解釈する（端末が和暦などでも崩れないように）。`DateFormatter` を新設するときも同様にすること。
- テスト: `ICSParserTests` / `ICSFeedClientTests`（`URLProtocol` スタブ）/ `SyncPlannerTests`（判定表の全マス）/ `SyncSupportTests`（`DueKey`・`SnapshotStore`・値変換）。EventKit への実書き込みはテストしない。
