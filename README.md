# klms-to-apple-reminders

慶應義塾大学の K-LMS（Canvas LMS）から課題を取得して、Apple リマインダーに自動追加する macOS メニューバーアプリ。

## 仕組み

```
K-LMS (Canvas API) → Swift macOS アプリ → EventKit → Apple リマインダー
```

- アプリ内ブラウザ（WKWebView）で K-LMS に一度 SSO ログイン
- ログイン後は Canvas セッション Cookie を使ってアクセストークンを自動生成・更新
- セッションが切れたらメニューバーのアイコンが変わり、ワンクリックで再ログイン
- トークンの手動発行・コピー&ペーストは一切不要
- 提出済み・重複した課題はスキップ
- トークンと Cookie は macOS Keychain に安全に保存

### 認証フロー

```
初回 / 再ログイン:
  WKWebView で SSO ログイン
       ↓
  canvas_session Cookie を Keychain に保存
       ↓
  Cookie で POST /api/v1/users/self/tokens → アクセストークン自動生成
       ↓
  トークンで通常の API 呼び出し

トークン期限切れ (401):
       ↓
  Cookie がまだ有効? ─── Yes ──▶ サイレントにトークン再生成（ユーザー操作不要）
       │ No
       ▼
  メニューバーアイコンが 🔓 に変化 → ユーザーに再ログインを通知
```

## セットアップ

### 1. ビルド & インストール

```bash
# プロジェクト生成（初回 or ファイル追加後）
xcodegen generate

# Release ビルドして /Applications にコピー
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project klms-to-apple-reminders.xcodeproj \
  -scheme klms-to-apple-reminders \
  -configuration Release \
  -derivedDataPath /tmp/klms-build

cp -R /tmp/klms-build/Build/Products/Release/klms-to-apple-reminders.app /Applications/
```

初回起動時は Finder で右クリック → **「開く」** で起動してください（Gatekeeper のダイアログをスキップするため）。

### 2. 初回設定（オンボーディング）

アプリを起動すると初回設定ウィザードが表示されます。

1. **リマインダーへのアクセスを許可する** → macOS のダイアログで「OK」
2. **同期設定を確認**（リスト名・タイミング・自動起動）→ **「K-LMS にログイン →」**
3. **アプリ内ブラウザで K-LMS にログイン**（SSOのダイアログが表示されます）
4. ログイン完了後、ウィンドウが自動で閉じます。これで設定完了です。

### 3. 動作確認

メニューバーのアイコンをクリック → **「今すぐ同期」** で課題が Apple リマインダーに追加されます。

## 機能

| 機能 | 説明 |
|---|---|
| 自動ログイン | SSO でログイン後、トークンを自動生成。手動発行不要 |
| 自動リフレッシュ | トークン期限切れを検知し、Cookie で自動再生成（操作不要） |
| 再ログイン通知 | セッション切れ時はメニューバーアイコンが 🔓 に変わり再ログインを促す |
| 自動同期 | 毎時間 / 毎日（時刻指定）/ 毎週（曜日・時刻指定） |
| 重複スキップ | 既にリマインダーにある課題・提出済み課題はスキップ |
| リスト自動作成 | 指定リストが存在しない場合は自動で作成 |
| ログイン時起動 | macOS ログイン時に自動起動（デフォルト ON） |

## ファイル構成

```
klms-to-apple-reminders/
├── App/
│   ├── KLMSToAppleRemindersApp.swift  # エントリーポイント
│   └── AppDelegate.swift              # 起動・サービス管理・ログインウィンドウ制御
├── Models/
│   ├── Assignment.swift               # 課題モデル
│   └── SyncResult.swift               # 同期結果モデル
├── Services/
│   ├── CanvasAuthService.swift        # Cookie → トークン生成・サイレントリフレッシュ
│   ├── KLMSClient.swift               # Canvas API クライアント
│   ├── RemindersService.swift         # EventKit 連携
│   ├── SchedulerService.swift         # 自動同期スケジューラ
│   └── SyncCoordinator.swift          # 同期処理・セッション状態管理
├── Storage/
│   ├── AppSettings.swift              # 設定 (UserDefaults)
│   ├── KeychainHelper.swift           # トークン・Cookie 保存 (Keychain)
│   └── TokenValidator.swift           # （内部用）
├── UI/
│   ├── CanvasLoginWindow.swift        # WKWebView SSO ログインウィンドウ
│   ├── MenuBarView.swift              # メニューバー UI（前回ログイン・再ログインボタン）
│   ├── OnboardingView.swift           # 初回設定ウィザード（2 ステップ）
│   ├── SettingsView.swift             # 設定画面
│   └── StatusItemManager.swift        # メニューバーアイコン管理
├── Info.plist
└── klms-to-apple-reminders.entitlements
```

## 動作環境

- macOS 13 (Ventura) 以上
- Xcode 15 以上（ビルド時のみ）
- 慶應義塾大学 K-LMS アカウント

## アプリのリセット

```bash
# オンボーディングのみリセット
plutil -replace hasCompletedOnboarding -bool NO \
  ~/Library/Preferences/io.github.tada246.klms-to-apple-reminders.plist

# 全設定をリセット
rm ~/Library/Preferences/io.github.tada246.klms-to-apple-reminders.plist

# Keychain のトークンと Cookie を削除
security delete-generic-password -s "io.github.tada246.klms-to-apple-reminders" -a "api-token"
security delete-generic-password -s "io.github.tada246.klms-to-apple-reminders" -a "canvas-session"

# リマインダー権限をリセット
tccutil reset Reminders io.github.tada246.klms-to-apple-reminders
```

## よくある質問

**Q: K-LMS へのログインはどのくらいの頻度で必要ですか？**
Canvas のセッション Cookie の有効期間に依存します。期限が切れると自動でサイレントリフレッシュを試み、それも失敗した場合のみメニューバーアイコンが変化して再ログインを促します。

**Q: 再ログインの方法は？**
メニューバーのアイコンをクリック → **「再ログイン」** ボタンを押すとアプリ内ブラウザが開きます。Shibboleth セッションが残っていれば自動でログインが完了します。

**Q: 課題が取得できない**
メニューバーアイコンをクリックして状態を確認してください。セッション切れの場合は「再ログイン」、その他のエラーはしばらく待ってから「今すぐ同期」を試してください。

**Q: リマインダーのリスト名を変えたい**
設定画面（メニューバーアイコン → 設定）から変更できます。

**Q: K-Pass（MFA）と共存できる？**
できます。アプリ内ブラウザがログイン画面をそのまま表示するため、MFA も通常どおり操作できます。

## ライセンス

MIT
