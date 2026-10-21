# Idioms And Type Safety Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Naming And Readability

Review 命名・可読性.

- 命名はリポジトリ既存の規約に一貫しているか。`data` / `info` のような情報量のない汎用語、`_data` サフィックスなど中身を表さない名前を避け、具体名を付けているか。
- データを組み立てる／構築するメソッドは `get` でなく `build` プレフィックスを使っているか（取得とビルドを名前で区別）。
- enum 的に扱う定数で網羅的に分岐する場合は `switch` を使い、`default` で未知値を弾いているか。
- 関数名と実処理に乖離がないか。単一責任になっており、長すぎないか。
- 一時的な作業メモや漠然とした TODO を残していないか（master にマージして問題ない内容のみ）。コメントは How/What（コード・命名・テストで表現すべき内容）でなく Why not（却下した代替案・トレードオフ・落とし穴）を説明しているか。
- ログ出力のレベルが用途に合っているか（ERROR=要対応の異常 / WARNING=注意 / INFO=通常の動作記録 / DEBUG=開発時の詳細）。正常系を ERROR で出す・異常を INFO に埋もれさせるといった取り違えがないか。
- 空行の使い方が整っているか（2 行以上の連続空行・メソッド本体の先頭/末尾の空行・プロパティ定義間の余分な空行を避け、論理ブロックの区切りに 1 行使う）。フォーマッタで機械的に担保できる範囲はそちらに委ね、明らかな読みにくさのみ指摘する。
- 1 行が過度に長く可読性を損なっていないか（無理な詰め込みは適切に改行・分割する。テストコードのデータ定義などは除外）。

Report only concrete readability risks, not subjective style preferences.

## Focus B: Type Declarations And PHPDoc

Review 型宣言・PHPDoc.

- `declare(strict_types=1)` の方針がプロジェクトとして統一されているか（有無・適用範囲）。引数・戻り値の型宣言が適切か（PHPDoc 依存になりすぎていないか）。
- PHPDoc は `mixed` を避け具体型を指定しているか。DB 由来の型は IDE Helper 生成の型定義（`_ide_helper_models.php` 等）に合わせているか。
- PHPDoc は `@param array` 等で済ませず array shape 記法で構造まで書いているか（例: `array<int, array{login_id: string, password: string}>`）。
- 親クラスが型なし（mixed）のメソッドをオーバーライドする場合、子で引数型を付けると反変性エラー（言語の互換性 + 静的解析）になる。子も型なしで定義し、内部 private メソッドへ切り出して `(string)` 等でキャストして渡しているか。

```php
// 親（型なし）をオーバーライドする子。引数には型を付けない
public function handle($value)
{
    return $this->doHandle((string) $value);
}

private function doHandle(string $value): string
{
    return trim($value);
}
```

- `@param` / `@return` の docblock を削除する前に、その型情報がメソッドシグネチャにあるか確認しているか。なければ先に型宣言へ移してから削除する。`array{key: type}` のような構造情報は型宣言で表せないため docblock に残す。

Report only concrete type-declaration or PHPDoc risks.

## Focus C: PHP Idioms And Correctness

Review PHP イディオム・実行時の正しさ.

- null 判定は `!== null` でなく `!is_null()`、肯定チェックは `is_null()` を使っているか。「値が取得できたか」を確認したいだけの場面で `$var instanceof ClassName` を使っていないか（instanceof は型一致まで表明し意図がぼやける。null チェックは `is_null($var)`）。
- 空値チェックは `=== ''` でなく `(!$variable)` を使っているか。配列の空判定は `empty()` でなく `=== []` / `!== []` を使っているか。
- 引数は ID 文字列ではなくモデル/エンティティのインスタンスを受け取り、存在保証と補完を効かせているか。
- `empty()` で必須値の有無を判定していないか（`'0'` / `0` / `false` を「空」と誤判定する。null 判定は `is_null()` / `??` を使う）。
- 正規表現の全体マッチに `^` / `$` ではなく `\A` / `\z` を使っているか（改行抜け穴防止）。PHPDoc 内の外部リンクは URL 直書きでなく `@link` タグを使っているか。
- 早期 return している if の後に不要な `else` を続けていないか。変数を使用ブロック内で定義しスコープを最小化しているか。
- 取得できない場合のフォールバックに `?? 'default'` のような sentinel 文字列を使っていないか（ルートパラメータ等）。`!$param` で早期 return し、呼び出し元の振る舞いに委ねているか（sentinel が正規値のように振る舞い、意図しない設定が適用されるリスク）。

Report only concrete PHP-idiom or runtime-correctness risks.
