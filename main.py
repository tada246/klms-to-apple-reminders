#!/usr/bin/env python3
import os
import sys
from dotenv import load_dotenv
from canvas_client import CanvasClient
from reminders import sync_assignments

load_dotenv()


def main():
    token = os.getenv("KLMS_API_TOKEN", "").strip()
    if not token or token == "your_token_here":
        print("エラー: KLMS_API_TOKEN が設定されていません。")
        print("  .env ファイルを作成して KLMS_API_TOKEN=<トークン> を設定してください。")
        print("  取得方法: https://lms.keio.jp/profile/settings → Approved Integrations → + New Access Token")
        sys.exit(1)

    list_name = os.getenv("REMINDERS_LIST", "慶應課題")
    days_ahead = int(os.getenv("DAYS_AHEAD", "30"))

    print(f"K-LMS から課題を取得中（{days_ahead}日以内）...")
    client = CanvasClient(token)

    try:
        assignments = client.get_upcoming_assignments(days_ahead)
    except Exception as e:
        print(f"エラー: K-LMS API への接続に失敗しました。\n  {e}")
        print("  トークンが正しいか、またはVPN/ネットワーク接続を確認してください。")
        sys.exit(1)

    if not assignments:
        print("未提出の課題は見つかりませんでした。")
        return

    print(f"{len(assignments)} 件の課題が見つかりました。Apple Reminders に同期中...")
    stats = sync_assignments(assignments, list_name)

    print(f"\n完了！")
    print(f"  追加: {stats['added']} 件")
    print(f"  スキップ（提出済み or 重複）: {stats['skipped']} 件")
    print(f"  リスト名: 「{list_name}」")


if __name__ == "__main__":
    main()
