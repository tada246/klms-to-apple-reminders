# klms-to-apple-reminders

慶應義塾大学の K-LMS（Canvas LMS）の課題を、Apple リマインダーに自動追加する macOS メニューバーアプリ。

## 仕組み

```
Canvas カレンダーフィード (.ics) → Swift macOS アプリ → EventKit → Apple リマインダー
```

- Canvas の **カレンダーフィード URL**（.ics）を一度貼り付けるだけ。K-LMS へのログインは不要
- フィード URL は SSO とは独立して長期間有効なので、再ログインは発生しない
- フィード URL は秘密トークンを含むため macOS Keychain に保存
- 課題の数値 ID で重複を判定し、追加済みの課題は追加しない（完了済みのリマインダーも含めて照合するので、完了にした課題が復活することはない）
- Canvas 側に Cookie・トークン・API は使わない（ICS only）

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
2. **同期設定を確認**（リスト名・タイミング・自動起動）→ **「完了」**
3. 設定画面が開くので、**Canvas のカレンダーフィード URL を貼り付けて「保存」**

### 3. カレンダーフィード URL の取得

Canvas（K-LMS）→ **カレンダー** → 画面の隅にある **「カレンダーフィード」** の URL をコピーします。`https://lms.keio.jp/feeds/calendars/user_xxxxx.ics` の形式です。

### 4. 動作確認

メニューバーのアイコンをクリック → **「今すぐ同期」** で課題が Apple リマインダーに追加されます。

## 機能

| 機能 | 説明 |
|---|---|
| ログイン不要 | カレンダーフィード URL を貼るだけ。SSO・Cookie・トークンは使わない |
| 自動同期 | 毎時間 / 毎日（時刻指定）/ 毎週（曜日・時刻指定） |
| 重複スキップ | 追加済みの課題（完了済み含む）は追加しない |
| リスト自動作成 | 指定リストが存在しない場合は自動で作成 |
| 期間指定 | 過去 1 日〜指定日数先（既定 30 日）の課題を対象にする |
| ログイン時起動 | macOS ログイン時に自動起動（デフォルト ON） |

## ファイル構成

```
klms-to-apple-reminders/
├── App/
│   ├── KLMSToAppleRemindersApp.swift  # エントリーポイント
│   └── AppDelegate.swift              # 起動・サービス管理・ウィンドウ制御
├── Models/
│   ├── Assignment.swift               # 課題モデル
│   └── SyncResult.swift               # 同期結果モデル
├── Services/
│   ├── ICSFeedClient.swift            # .ics 取得 + 最小 ICS パーサ
│   ├── RemindersService.swift         # EventKit 連携・課題 ID による重複判定
│   ├── SchedulerService.swift         # 自動同期スケジューラ
│   └── SyncCoordinator.swift          # 同期処理・設定状態管理
├── Storage/
│   ├── AppSettings.swift              # 設定 (UserDefaults)
│   └── KeychainHelper.swift           # フィード URL の保存 (Keychain)
├── UI/
│   ├── MenuBarView.swift              # メニューバー UI
│   ├── OnboardingView.swift           # 初回設定ウィザード（2 ステップ）
│   ├── SettingsView.swift             # 設定画面（フィード URL 入力を含む）
│   └── StatusItemManager.swift        # メニューバーアイコン管理
├── Assets.xcassets/                   # アプリアイコン
├── Info.plist
└── klms-to-apple-reminders.entitlements
```

設計メモは `docs/` を参照（`ics-migration.md`: ICS 方式へ移行した経緯、`design-issues-4-5-7.md`: イシュー対応の設計書）。

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

# Keychain のフィード URL を削除
security delete-generic-password -s "klms-to-apple-reminders" -a "ics-feed-url"

# リマインダー権限をリセット
tccutil reset Reminders io.github.tada246.klms-to-apple-reminders
```

## よくある質問

**Q: K-LMS へのログインは必要ですか？**
不要です。カレンダーフィード URL は秘密トークンを含み、ログインとは独立して有効です。

**Q: フィード URL を再発行したら？**
設定画面（メニューバーアイコン → 設定）で新しい URL を貼り付けて保存してください。

**Q: 課題を提出したらリマインダーは自動で完了になりますか？**
なりません。カレンダーフィードに提出状態が含まれないためです。リマインダーを手で完了にすれば、次回以降の同期でも復活しません。

**Q: 課題が取得できない**
メニューバーアイコンをクリックして状態を確認してください。「フィード URL が未設定」の場合は設定画面で URL を貼り付けます。HTTP エラーが出る場合は URL が正しいか確認し、再発行した場合は貼り直してください。

**Q: 特定の課題が出てこない**
課題は UID が `event-assignment-` で始まるカレンダーイベントのみが対象です。教員が作った単なるカレンダーイベントは対象外です。また、期間は「過去 1 日〜設定した日数先」で、設定画面の「取得日数」で変更できます。

**Q: リマインダーのリスト名を変えたい**
設定画面（メニューバーアイコン → 設定）から変更できます。

## ライセンス

MIT
