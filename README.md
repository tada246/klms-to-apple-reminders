# klms-to-todo

慶應義塾大学の K-LMS（Canvas LMS）から課題を取得して、Apple Reminders に自動追加するツール。

> MFAが毎回必要なK-LMSのログインを、APIトークン一度の発行で解決します。

## 仕組み

```
K-LMS (Canvas API) → Python スクリプト → Apple Reminders
```

- APIトークンを一度発行すれば、以後 MFA なしで課題一覧を取得
- 提出済み・重複した課題はスキップ
- 毎朝 launchd で自動実行可能（macOS）

## セットアップ

### 1. リポジトリをクローン

```bash
git clone https://github.com/<your-username>/klms-to-todo.git
cd klms-to-todo
bash setup.sh
```

### 2. APIトークンを発行

1. [https://lms.keio.jp/profile/settings](https://lms.keio.jp/profile/settings) を開く
2. **「Approved Integrations」** セクションへスクロール
3. **「+ New Access Token」** をクリック
4. 目的を入力（例: `klms-to-todo`）して生成
5. 表示されたトークンをコピー（再表示不可）

### 3. .env を編集

```bash
# .env
KLMS_API_TOKEN=your_token_here
REMINDERS_LIST=慶應課題   # Reminders に作成するリスト名
DAYS_AHEAD=30              # 何日先まで取得するか
```

### 4. 実行

```bash
source .venv/bin/activate
python main.py
```

初回実行時、macOS が Reminders へのアクセス許可を求めます。**「OK」** をクリックしてください。

### 5. 毎朝8時に自動実行（オプション）

```bash
bash setup_launchd.sh
```

## ファイル構成

```
klms-to-todo/
├── main.py           # エントリーポイント
├── canvas_client.py  # Canvas API クライアント
├── reminders.py      # Apple Reminders 連携（osascript）
├── setup.sh          # 初期セットアップ
├── setup_launchd.sh  # macOS 自動実行設定
├── requirements.txt
└── .env.example
```

## 動作環境

- macOS 12 以上（Apple Reminders が必要）
- Python 3.11 以上
- K-LMS（慶應義塾大学）のアカウント

## よくある質問

**Q: トークンの有効期限は？**
Canvas のデフォルトでは有効期限なし。K-LMS の設定によっては期限が設けられている場合があります。切れた場合は再発行してください。

**Q: K-Pass と共存できる？**
できます。このツールは Canvas API を使うのみで、K-Pass の動作には影響しません。

**Q: 課題が取得できない**
トークンが正しいか確認してください。また、Keio の VPN 接続が必要な場合があります。

## ライセンス

MIT
