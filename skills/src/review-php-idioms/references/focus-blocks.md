# Idioms And Type Safety Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Naming And Readability

Review 命名・可読性.

- 命名はリポジトリ既存の規約に一貫しているか。`data` / `info` のような情報量のない汎用語を避けているか。
- enum 的に扱う定数で網羅的に分岐する場合は `switch` を使い、`default` で未知値を弾いているか。
- 関数名と実処理に乖離がないか。単一責任になっており、長すぎないか。
- 一時的な作業メモや漠然とした TODO を残していないか（master にマージして問題ない内容のみ）。コメントは「何をするか」でなく「なぜそうするか」を説明しているか。
- ログ出力のレベルが用途に合っているか（ERROR=要対応の異常 / WARNING=注意 / INFO=通常の動作記録 / DEBUG=開発時の詳細）。正常系を ERROR で出す・異常を INFO に埋もれさせるといった取り違えがないか。
- 空行の使い方が整っているか（2 行以上の連続空行・メソッド本体の先頭/末尾の空行・プロパティ定義間の余分な空行を避け、論理ブロックの区切りに 1 行使う）。フォーマッタで機械的に担保できる範囲はそちらに委ね、明らかな読みにくさのみ指摘する。
- 1 行が過度に長く可読性を損なっていないか（無理な詰め込みは適切に改行・分割する。テストコードのデータ定義などは除外）。

Report only concrete readability risks, not subjective style preferences.

## Focus B: Type Safety And PHP Idioms

Review 型安全性・PHP イディオム.

- `declare(strict_types=1)` の方針がプロジェクトとして統一されているか（有無・適用範囲）。引数・戻り値の型宣言が適切か（PHPDoc 依存になりすぎていないか）。
- PHPDoc は `mixed` を避け具体型を指定しているか。DB 由来の型は IDE Helper 生成の型定義（`_ide_helper_models.php` 等）に合わせているか。
- 引数は ID 文字列ではなくモデル/エンティティのインスタンスを受け取り、存在保証と補完を効かせているか。
- `empty()` で必須値の有無を判定していないか（`'0'` / `0` / `false` を「空」と誤判定する。null 判定は `is_null()` / `??` を使う）。
- 正規表現の全体マッチに `^` / `$` ではなく `\A` / `\z` を使っているか（改行抜け穴防止）。PHPDoc 内の外部リンクは URL 直書きでなく `@link` タグを使っているか。
- 早期 return している if の後に不要な `else` を続けていないか。変数を使用ブロック内で定義しスコープを最小化しているか。

Report only concrete type-safety or correctness risks.
