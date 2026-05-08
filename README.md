# klms-to-apple-reminders

慶應義塾大学の K-LMS（Canvas LMS）から課題を取得して、Apple Reminders に自動追加する macOS メニューバーアプリ。

> MFAが毎回必要なK-LMSのログインを、APIトークン一度の発行で解決します。

## 仕組み

```
K-LMS (Canvas API) → Swift macOS アプリ → EventKit → Apple Reminders
```

- APIトークンを一度発行すれば、以後 MFA なしで課題一覧を取得
- 提出済み・重複した課題はスキップ
- メニューバーから手動同期 or 自動スケジュール実行に対応
- トークンは macOS Keychain に安全に保存

## セットアップ

### 1. APIトークンを発行

1. [https://lms.keio.jp/profile/settings](https://lms.keio.jp/profile/settings) を開く
2. **「Approved Integrations」** セクションへスクロール
3. **「+ New Access Token」** をクリック
4. 目的を入力（例: `klms-to-apple-reminders`）して生成
5. 表示されたトークンをコピー（再表示不可）

### 2. ビルド & 実行

Xcode でプロジェクトを開いてビルドします。

```bash
open klms-to-apple-reminders.xcodeproj
```

または [XcodeGen](https://github.com/yonaskolb/XcodeGen) を使用している場合:

```bash
xcodegen generate
open klms-to-apple-reminders.xcodeproj
```

### 3. 初回設定

1. アプリを起動するとメニューバーにアイコンが表示される
2. アイコンをクリック → **「設定」** を開く
3. APIトークンを入力して保存
4. Reminders へのアクセス許可を求めるダイアログで **「OK」** をクリック
5. **「今すぐ同期」** で動作確認

## ファイル構成

```
klms-to-apple-reminders/
├── App/
│   ├── KLMSToAppleRemindersApp.swift  # アプリエントリーポイント
│   └── AppDelegate.swift              # AppDelegate
├── Models/
│   ├── Assignment.swift               # 課題モデル
│   └── SyncResult.swift               # 同期結果モデル
├── Services/
│   ├── KLMSClient.swift               # Canvas API クライアント
│   ├── RemindersService.swift         # EventKit (Apple Reminders) 連携
│   ├── SchedulerService.swift         # 自動同期スケジューラ
│   └── SyncCoordinator.swift          # 同期処理の統括
├── Storage/
│   ├── AppSettings.swift              # アプリ設定 (UserDefaults)
│   └── KeychainHelper.swift           # トークンの安全な保存 (Keychain)
├── UI/
│   ├── MenuBarView.swift              # メニューバー UI
│   ├── SettingsView.swift             # 設定画面
│   └── StatusItemManager.swift        # メニューバーアイコン管理
├── Info.plist
├── klms-to-apple-reminders.entitlements
└── klms-to-apple-reminders.xcodeproj/
```

## 動作環境

- macOS 13 (Ventura) 以上
- Xcode 15 以上
- K-LMS（慶應義塾大学）のアカウント

## よくある質問

**Q: トークンの有効期限は？**
Canvas のデフォルトでは有効期限なし。K-LMS の設定によっては期限が設けられている場合があります。切れた場合は再発行してください。

**Q: K-Pass と共存できる？**
できます。このアプリは Canvas API を使うのみで、K-Pass の動作には影響しません。

**Q: 課題が取得できない**
設定画面でトークンが正しく入力されているか確認してください。また、Keio の VPN 接続が必要な場合があります。

**Q: Reminders のリスト名を変えたい**
設定画面から Reminders リスト名を変更できます。

## ライセンス

MIT
