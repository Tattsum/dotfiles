# Architecture Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Layer Responsibility

Review Controller / UseCase・Service / Eloquent Model の責務境界.

- Controller が肥大化していないか。条件分岐・フィルタリング・計算といったビジネスロジックは UseCase / Service に切り出されているか。Controller は「入力受け取り → ユースケース呼び出し → レスポンス整形」に徹しているか。
- Eloquent Model にビジネスロジックを詰め込みすぎていないか。複雑なユースケース組み立てが Model のメソッドに漏れていないか。レスポンス整形は API Resource、入力検証は FormRequest に分離されているか。
- レスポンス都合の型変換（UNIX タイムスタンプ化・日付フォーマット等）を Model で行わず、境界（API Resource）で変換しているか。
- 入力検証が Controller 内に散らばっていないか。バリデーションは FormRequest に集約されているか（`is_string` 等の型チェックを Controller で書いている時点で FormRequest 化を検討）。
- ドメイン知識が本来所属するクラス/モジュールに置かれているか（別ドメインの分岐・フィルタを呼び出し側に書いていないか）。
- Eloquent Model の `boot()` の `creating` イベントでフィールドバリデーションをしていないか（`create()` 時のみ発火し `insert()` では走らない不完全なガードになり、隠れた副作用で認知負荷が高い）。有効値は public 定数で定義し呼び出し元が明示的に使う。PHP 8.1+ なら Enum を cast に指定する。

Report only responsibility leaks that are visible in the changed code.

## Focus B: Transaction Boundary And Class Design

Review トランザクション境界・イミュータブル設計・YAGNI・クラス構成.

- トランザクション境界（`DB::transaction()`）が適切か。複数の書き込みが原子性を必要とするのに個別実行になっていないか。逆に不要に広いトランザクションで外部 API 呼び出し等を巻き込んでいないか。
- 既存インスタンスを破壊的に変更するより、新インスタンスを生成するイミュータブルな実装を優先しているか。
- **YAGNI**: 現時点で使われないメソッド・プロパティ・クラス・引数を追加していないか。上流で保証済みの条件を再チェックする防御的コードを書いていないか。
- クラス内定義順が「定数 → プロパティ → コンストラクタ → メソッド」になっているか。FQCN をインラインで書かず `use` でインポートしているか。全メソッドに戻り値型宣言（`: void` / `: ?int` 等）が付いているか。

Report only concrete maintainability or correctness risks, not broad style preferences.
