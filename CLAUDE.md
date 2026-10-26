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
      → ICSFeedClient(feedURL:).fetchAssignments(daysAhead:)
          → .ics を HTTP GET（Bearer 不要）
          → 最小 ICS パーサで VEVENT を抽出
          → UID が "event-assignment-" で始まるものだけを Assignment 化
      → RemindersService.existingAssignmentIDs(in:) で既存の課題 ID 集合を取得（完了済みも含む）
      → 未登録の課題 ID のみ addReminder
  URL 未設定なら isConfigured=false、onNeedsConfiguration → AppDelegate が設定を開く
```

**ICS パーサ**（`ICSFeedClient.swift` 内 `ICSParser`）: 行アンフォールディング、`BEGIN/END:VEVENT` 抽出、`UID`/`SUMMARY`/`DTSTART`/`URL` 取得、ICS エスケープ解除、DTSTART の3形式（末尾 Z の UTC / `VALUE=DATE` 終日 / `TZID` 付き）に対応。SUMMARY 末尾の `[コース名]` を分離。前提とする実 VEVENT サンプルはファイル冒頭コメント参照。

**.ics の制約と対処**: フィードには提出済みフラグが無い（提出で自動完了にはできない。ICS only 方針のため Canvas API・トークンは使わない）。そのため重複回避は Canvas API の `submitted` ではなく **課題の数値 ID** で行う。UID（`event-assignment-1269269`）とリマインダーの `url`（`…/assignments/1269269`）の両方から同じ ID を正規表現で取り出して突き合わせる（`RemindersService.assignmentID(...)`）。notes にマーカーは埋めない（`eaa7b0f` で廃止）。既存リマインダーは **完了済みを含めて** 走査する。完了課題が再同期で復活しないようにするため。

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
- **`KeychainHelperTests`** は `.setUp`/`.tearDown` で `KeychainHelper.deleteFeedURL()` を呼ぶ。`RemindersServiceTests` は課題 ID 抽出（純粋関数）のみを検証し、EventKit には触れない。
- ユーザーが削除したリマインダーは次回同期で復活する（完了済みは復活しない）。
- 課題判定は UID プレフィックス `event-assignment-`（クイズも Canvas ではこの系）。他の Canvas インスタンスでは UID 形式が異なる場合がある。
- 期間フィルタは `now-1日` 〜 `now+daysAhead日`。過去1日を含めるのは締切直後の未提出課題を取りこぼさないため。
