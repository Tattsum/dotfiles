# Observability Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Log Context And Coverage

Review 調査可能性のためのログコンテキスト付与と異常系のログ網羅.

- 調査に必要なコンテキストをログに付与しているか（`Log::withContext([...])` で対象エンティティの識別子・テナント識別子・クラス名等）。後から特定のリクエスト/対象を追跡できるようになっているか。
- 失敗・未到達・空結果（探したが見つからなかった等）の分岐でログを残し、原因を追えるようにしているか。正常系だけログして異常系を無言で返していないか。
- 識別子のないログ（「処理に失敗しました」だけ等）になっていないか。どの対象・どのリクエストで起きたかを後から特定できるか。

Report only concrete investigability gaps where a failure or empty result could not be traced from the logs.

## Focus B: Log Centralization, Secrets, And Levels

Review 例外ログの一元化・秘匿情報の非出力・ログレベルの整合.

- 例外処理は利用側で個別にログせず、基底コントローラ等で一元化しているか。利用側は例外を投げるだけにして、ログとレスポンス整形を重複させていないか。
- 一元化された例外ハンドリングで重大度ごとに出し分けているか（4xx 相当は Warning、5xx 相当は Error / 監視通知 など）。
- 秘匿情報（トークン・パスワード・個人情報）をログに出していないか（観測性と機密保護の両立。秘匿値そのもののマスク方針は security 観点に委ねる）。
- ログレベルが内容と整合しているか（想定内の入力エラーを Error で出して監視を汚していないか、重大な障害を info/debug に落としていないか）。

Report only concrete risks of duplicated/centralized-bypassing logs, secret leakage into logs, or mismatched log levels.
