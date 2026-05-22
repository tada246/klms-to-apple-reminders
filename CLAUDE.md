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

**依存フレームワーク**: WebKit のみ（`project.yml` で明示リンク）。サンドボックスは無効（`entitlements` で `app-sandbox = false`）。

## アーキテクチャ概要

### 全体のデータフロー

```
Canvas API (lms.keio.jp)
    ↓ KLMSClient（Bearer token）
SyncCoordinator（@MainActor, ObservableObject）
    ↓ RemindersService（EventKit）
Apple リマインダー
```

- **`KLMSToAppleRemindersApp`**: `@main`。WindowGroup を使わず、`AppDelegate` を `@NSApplicationDelegateAdaptor` で使うメニューバー専用構成。
- **`AppDelegate`**: 全ウィンドウのライフサイクル管理（オンボーディング・ログイン・設定）。`SyncCoordinator` と `SchedulerService` のオーナー。
- **`SyncCoordinator`**: `@MainActor` の `ObservableObject`。同期状態（`isSyncing`, `lastError`, `isSessionExpired`, `lastLoginDate`）を持ち、UI が購読する。
- **`StatusItemManager`**: `coordinator.objectWillChange` を購読してメニューバーアイコンを更新。

### 認証フロー（最重要）

K-LMS は Keio の SAML/Shibboleth SSO を使っており、Canvas 個人アクセストークンが SSO セッションに紐付いて数時間で失効する。これを解決するため、Bearer トークンと Cookie の二段構成を取る。

```
初回 / 再ログイン:
  CanvasLoginWindow（WKWebView）で SSO ログイン
      ↓ WKHTTPCookieStore から canvas_session Cookie を抽出
  CanvasAuthService.generateToken(cookieHeader:)
      → POST /api/v1/users/self/tokens（Cookie + X-CSRF-Token ヘッダー）
      → レスポンスの "token" / "visible_token" フィールドを取得
  Keychain に token（account: "api-token"）と cookie（account: "canvas-session"）を保存
  UserDefaults の "lastLoginDate" に Date を記録

通常の同期:
  KeychainHelper.load() → KLMSClient(token:) → fetchAssignments

401（トークン期限切れ）を受け取ったとき（SyncCoordinator.performSync）:
  CanvasAuthService.silentRefresh()
    → KeychainHelper.loadCookie() で cookie を取得
    → 再度 POST /api/v1/users/self/tokens → 成功なら新トークンを Keychain に保存
  → 成功: リトライ（isRetry: true で無限ループ防止）
  → 失敗: isSessionExpired = true、onSessionExpired コールバック → AppDelegate がログインウィンドウを表示
```

**CSRF トークン**: Canvas は `_csrf_token` Cookie に URL エンコードされた CSRF トークンを入れている。`POST /api/v1/users/self/tokens` の際、URL デコードして `X-CSRF-Token` ヘッダーにセットする必要がある（`CanvasAuthService.extractCSRFToken` 参照）。

**WKWebView のデータストア**: `WKWebsiteDataStore.default()`（永続ストア）を使っている。Shibboleth の SSO セッションが残っていれば再ログイン時に自動完結するため。非永続ストアに変えると毎回 MFA が必要になる。

### Keychain のキー構造

| account | 内容 |
|---|---|
| `"api-token"` | Canvas Bearer トークン |
| `"canvas-session"` | Cookie ヘッダー文字列（`name=value; name=value; ...`） |

### セッション状態と UI の対応

| `isSessionExpired` | アイコン | メニュー |
|---|---|---|
| false, syncing | `arrow.clockwise` | 通常 |
| false, error | `exclamationmark.circle` | 通常 |
| false, 正常 | `checklist` | 通常 |
| **true** | **`lock.open.fill`** | **「再ログイン」ボタンが「終了」の上に追加** |

### 並行処理の注意点

- `SyncCoordinator` と `RemindersService` は `@MainActor`。
- `CanvasLoginWindowController.handleLoginSuccess` は `@MainActor` で宣言し、`Task { @MainActor in ... }` で呼ぶ。
- `AppDelegate` のクロージャから `coordinator`（MainActor）を呼ぶときは `Task { @MainActor [weak self] in ... }` が必要。

### スケジューラ

`SchedulerService` は `Timer` ベース（`RunLoop.main`）。`SyncInterval` は `hourly / daily / weekly` の3種。`AppDelegate.openSettings` のコールバックでスケジュールを再設定する。

## 既知の注意点

- **`TokenValidator.swift`** は現在コード上では使われていないが、テスト（`TokenValidatorTests`）がまだ存在するため削除しないこと。
- **テストの `KeychainHelperTests`**: `.setUp`/`.tearDown` でトークンを削除しているが、Cookie のクリーンアップはまだない。Cookie のテストを追加するなら `KeychainHelper.deleteCookie()` を `tearDown` に追加すること。
- Canvas API のトークン生成レスポンスフィールドは `"token"` か `"visible_token"` の両方を試している（Canvas バージョンによって異なる可能性があるため）。
- `CanvasLoginWindow` でログイン成功検出は「lms.keio.jp 上 かつ /login を含まない URL に遷移 かつ `canvas_session` Cookie が存在する」で判定。他の Canvas インスタンスでは URL パターンが異なる場合がある。
