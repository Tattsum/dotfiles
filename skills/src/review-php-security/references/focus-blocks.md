# Security Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Injection And Mass Assignment

Review インジェクション・マスアサインメント・XSS.

- SQL インジェクション: 生クエリ / `DB::raw` / 文字列連結を避け、バインド（プレースホルダ）を使っているか。外部入力を WHERE / ORDER BY 等に直接埋め込んでいないか。
- マスアサインメント: `$fillable` / `$guarded` が適切に設定され、ユーザー入力をそのまま `create()` / `update()` / `fill()` に渡していないか。
- XSS: Blade の `{!! !!}`（unescaped）やフロントへ渡す HTML 文字列で、ユーザー入力をエスケープせず出力していないか。
- URL の処理に `strings`/`explode` でなく適切なパーサを使い、外部値を URL パラメータに埋め込む際にエスケープしているか。

Report only concrete injection / XSS risks reachable from external input.

## Focus B: Authorization And Secret Handling

Review 認可・テナント分離・機微情報・入力検証.

- 認証・認可（Policies / Gates / Middleware）のチェックが漏れていないか。リソース取得・更新・削除に対する所有者/権限チェックがあるか。
- マルチテナントで他テナントのデータが混ざらないか（テナント ID スコープの徹底。クエリに tenant_id 条件が漏れていないか）。
- 機微情報（トークン・パスワード・PII）をログ・例外メッセージ・レスポンスに出していないか。例外に SQL / 認証情報が含まれていないか。
- 平文の秘匿値（アクセストークン等）を生の配列・文字列で持ち回っていないか。値オブジェクトにラップし `__toString` / `__debugInfo` でマスクして、ログやダンプへの平文漏洩を防いでいるか。
- 入力値のバリデーションがされているか（クライアント任せでなくサーバ側 FormRequest で検証しているか）。例外の粒度が適切で、catch-all で握りつぶしていないか。

Report only concrete authorization gaps or information-disclosure risks.
