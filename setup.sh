#!/bin/bash
set -e

echo "=== klms-to-todo セットアップ ==="

# Python 3.11+ チェック
if ! command -v python3 &>/dev/null; then
    echo "エラー: python3 がインストールされていません。"
    exit 1
fi

# 仮想環境作成
if [ ! -d ".venv" ]; then
    echo "仮想環境を作成中..."
    python3 -m venv .venv
fi

source .venv/bin/activate
pip install -q -r requirements.txt

# .env 作成
if [ ! -f ".env" ]; then
    cp .env.example .env
    echo ""
    echo "✅ .env ファイルを作成しました。"
    echo ""
    echo "次のステップ:"
    echo "  1. https://lms.keio.jp/profile/settings を開く"
    echo "  2. 「Approved Integrations」→「+ New Access Token」をクリック"
    echo "  3. 発行されたトークンを .env の KLMS_API_TOKEN= に貼り付ける"
    echo ""
else
    echo "✅ .env はすでに存在します。"
fi

echo ""
echo "実行方法:"
echo "  source .venv/bin/activate"
echo "  python main.py"
echo ""
echo "自動実行（毎朝8時）の設定:"
echo "  bash setup_launchd.sh"
