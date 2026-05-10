# klms-to-apple-reminders

慶應義塾大学の K-LMS（Canvas LMS）から課題を取得して、Apple リマインダーに自動追加する macOS メニューバーアプリ。

> MFAが毎回必要なK-LMSのログインを、APIトークン一度の発行で解決します。

## 仕組み

```
K-LMS (Canvas API) → Swift macOS アプリ → EventKit → Apple リマインダー
```

- APIトークンを一度発行すれば、以後 MFA なしで課題一覧を取得
- 提出済み・重複した課題はスキップ
- メニューバーから手動同期、または自動スケジュール（毎時間・毎日・毎週）
- トークンは macOS Keychain に安全に保存

## セットアップ

### 1. APIトークンを発行

1. [https://lms.keio.jp/profile/settings](https://lms.keio.jp/profile/settings) を開く
2. **「承認済みのアプリケーション」** セクションへスクロール
3. **「新しいアクセストークン」** をクリック
4. 目的を入力（例: `KLMS to Apple リマインダー`）
5. 有効期限は空白（または任意の期間）のまま → **「トークンの生成」**
6. 表示されたトークンをコピー（**画面を閉じると再表示不可**）

### 2. ビルド & インストール

```bash
# プロジェクト生成（初回 or ファイル追加後）
xcodegen generate

# Releaseビルドして /Applications にコピー
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project klms-to-apple-reminders.xcodeproj \
  -scheme klms-to-apple-reminders \
  -configuration Release \
  -derivedDataPath /tmp/klms-build

cp -R /tmp/klms-build/Build/Products/Release/klms-to-apple-reminders.app /Applications/
```

初回起動時は Finder で右クリック → **「開く」** で起動してください（Gatekeeper のダイアログをスキップするため）。

### 3. 初回設定（オンボーディング）

アプリを起動すると初回設定ウィザードが表示されます。

1. **リマインダーへのアクセスを許可する** → macOS のダイアログで「OK」
2. **APIトークンを入力**（英数字のみ）
3. **同期設定を確認**（リスト名・タイミング・自動起動）→ **「はじめる」**

### 4. 動作確認

メニューバーのアイコンをクリック → **「今すぐ同期」** で課題が Apple リマインダーに追加されます。

## 機能

| 機能 | 説明 |
|---|---|
| 自動同期 | 毎時間 / 毎日（時刻指定）/ 毎週（曜日・時刻指定） |
| 重複スキップ | 既にリマインダーにある課題・提出済み課題はスキップ |
| リスト自動作成 | 指定リストが存在しない場合は自動で作成 |
| ログイン時起動 | macOS ログイン時に自動起動（デフォルト ON） |
| トークン検証 | 英数字以外の入力をリアルタイムで検出 |

## ファイル構成

```
klms-to-apple-reminders/
├── App/
│   ├── KLMSToAppleRemindersApp.swift  # エントリーポイント
│   └── AppDelegate.swift              # 起動・サービス管理
├── Models/
│   ├── Assignment.swift               # 課題モデル
│   └── SyncResult.swift               # 同期結果モデル
├── Services/
│   ├── KLMSClient.swift               # Canvas API クライアント
│   ├── RemindersService.swift         # EventKit 連携
│   ├── SchedulerService.swift         # 自動同期スケジューラ
│   └── SyncCoordinator.swift          # 同期処理の統括
├── Storage/
│   ├── AppSettings.swift              # 設定 (UserDefaults)
│   ├── KeychainHelper.swift           # トークン保存 (Keychain)
│   └── TokenValidator.swift           # トークン形式チェック
├── UI/
│   ├── MenuBarView.swift              # メニューバー UI
│   ├── OnboardingView.swift           # 初回設定ウィザード
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

# APIトークンを削除
security delete-generic-password -s "io.github.tada246.klms-to-apple-reminders"

# リマインダー権限をリセット
tccutil reset Reminders io.github.tada246.klms-to-apple-reminders
```

## よくある質問

**Q: トークンの有効期限は？**
有効期限なしで発行した場合は無期限。切れた場合は K-LMS で再発行し、設定画面から更新してください。

**Q: 課題が取得できない**
設定画面でトークンが正しく入力されているか確認してください。英数字のみ有効です。

**Q: リマインダーのリスト名を変えたい**
設定画面（メニューバーアイコン → 設定）から変更できます。

**Q: K-Pass（MFA）と共存できる？**
できます。このアプリは Canvas API のみ使用し、K-Pass の動作には影響しません。

## ライセンス

MIT
