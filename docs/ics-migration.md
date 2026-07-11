# .ics フィード方式への移行メモ

## 背景（なぜ旧 SSO 方式を捨てたか）

旧方式は WKWebView で Keio SSO（SAML/Shibboleth）ログイン → `canvas_session` Cookie から Canvas 個人アクセストークンを動的生成 → Bearer で `/api/v1/planner/items` を叩いていた。SSO セッションが数時間で失効し、その都度ブラウザ再ログインが必要で運用が重かった。

Canvas のカレンダーフィード（.ics）URL はユーザーごとの秘密トークンを URL に内包し、SSO とは独立して長期間有効。ログインは「URL を一度貼るだけ」になり、認証・Cookie・トークン・セッション失効・再ログインのコードがすべて不要になった。

## 新アーキテクチャ

```
Canvas カレンダーフィード (.ics, 秘密トークン内包)
    ↓ ICSFeedClient（Bearer 不要の HTTP GET + 最小 ICS パーサ）
SyncCoordinator（@MainActor, ObservableObject）
    ↓ RemindersService（EventKit, UID による重複回避）
Apple リマインダー
```

- **フィード URL の保管**: Keychain（account: `ics-feed-url`）。秘密トークンを含むため。
- **課題の抽出**: ICS の VEVENT のうち、UID が `event-assignment-` で始まるものだけを課題/クイズとして採用。
- **締切**: VEVENT の DTSTART。UTC（末尾 Z）／終日（`VALUE=DATE`）／`TZID` 付きの3形式に対応。
- **期間フィルタ**: `now - 1日` 〜 `now + daysAhead日`。過去1日を含めるのは締切直後の未提出課題を取りこぼさないため。

## .ics の構造的制約と対処

- **提出済みフラグが無い**: 旧 API の `submitted` に相当する情報がフィードには無い。そのため「提出済みだから追加しない」判定はできない。
  - 対処: ICS の安定した **UID による重複回避**。リマインダー作成時に notes 末尾へ不可視マーカー `[klms:<uid>]` を埋め、次回同期時に既存リマインダー（**完了済みも含む**）の UID 集合と突き合わせて未登録のみ追加する。完了済みも走査するのは、完了した課題が再同期で復活しないようにするため。
- **課題以外のイベントが混ざる**: 教員が作成したカレンダーイベント等も VEVENT として入る。UID プレフィックス `event-assignment-` で課題のみに絞る。

## ICS パーサが前提とするフォーマット

`Services/ICSFeedClient.swift` のヘッダコメントに代表的な VEVENT サンプルを記載している。将来 Canvas 側のフォーマットが変わったら、実フィードの出力とそのサンプルを diff して `parseVEvents` / `parseDate` を調整する。

## 検証手順

1. Canvas → カレンダー → 「カレンダーフィード」の URL を取得。
2. `curl -s '<feed-url>' | head -60` で .ics の VEVENT 構造を目視確認。
3. アプリの設定に URL を貼り付け → 手動同期 → 「慶應課題」リストに課題が入る。
4. 2回目の同期で重複追加が 0 件。
5. リマインダーを1件完了 → 再同期しても復活しない。
