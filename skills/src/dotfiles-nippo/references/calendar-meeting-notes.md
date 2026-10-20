# カレンダー・議事録の補足

[共通の取得・採用基準](external-activity.md)を適用する。このファイルは Calendar 固有の取得手順。
カレンダーは議事録を探す入口にする。予定・招待への承諾・参加者一覧だけで、
出席や作業完了を確定しない。本人の記述が無ければ、その会議は日報に載せない。

## 取得する

接続済みの読み取りツールを使う。未接続なら補足を省き、ログからの生成を続ける。
この手順のために新しい連携・認証・依存を導入しない。

1. Calendar のプロフィール（`google_calendar_get_profile`）から本人の氏名・メールを確認する。
   議事録の発言者・担当者と一意に対応する表記だけを本人として扱う。同姓同名や曖昧な略称は
   推測で対応付けず、その項目を除外する。資料の所有者・編集者であることも作業の根拠にしない。
2. `google_calendar_search_events` で既定は `primary` の対象日だけを検索する。
   ユーザーが別のカレンダーを指定した場合だけ、そのカレンダーを使う。
   日付は digest の `meta.date`、未取得なら生成手順 1 の対象日を使う。
   日付境界はログと同じタイムゾーンの当日 00:00 から翌日 00:00 までの RFC3339 で指定し、
   `timezone_str` にも同じ IANA 名を渡す。この利用者の既定は `Asia/Tokyo`。
   `meta.timezone` の `JST` 等の略称をそのまま IANA 名として渡さない。
   `next_page_token` があれば同じ範囲で続け、検索日を広げない。
3. `google_calendar_read_event` で必要な予定の詳細を読む。キャンセル済み・本人が辞退した予定を除き、
   説明欄のリンクや添付（`attachments[].fileUrl` / `fileId`）から議事録を特定する。
   繰り返し予定は対象日の回を確認し、親予定だけから開催日を推測しない。
   日付・状態を確認できない予定は部分取得として除外する。
4. Google Docs は `google_drive_get_document_text` 等の文書専用の読み取りツールを使う。
   リンクのタブ指定があればそのタブを読み、無ければ全タブから対象日の節を確認する。
   複数日を含む通年議事録では対象日の会議の節だけを使う。
   Confluence / Notion 等は、そのサービスの読み取り連携が利用できる場合だけ取得する。
   必要なサービス固有のスキルがあれば従い、本文の編集・投稿はしない。

ツール名が異なる環境では同等の読み取りツールを使い、無ければ未接続として扱う。
同じ文書・タブは重複取得しない。予定から直接リンクされた資料までで取得を止め、
議事録本文の関連リンク・フォルダ一覧・文書履歴・別日の予定へ広げない。

## 仕様の確認先

- [Calendar の予定](https://developers.google.com/workspace/calendar/api/v3/reference/events): 説明欄、添付、状態、招待への回答
- [Calendar の日付範囲](https://developers.google.com/workspace/calendar/api/v3/reference/events/list): 日付をまたぐ予定、ページング、繰り返し予定
- [Google Docs のタブ](https://developers.google.com/workspace/docs/api/how-tos/tabs): 複数タブの読み取り
