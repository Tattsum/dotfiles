# Test Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Test Naming And Structure

Review テスト命名・構造.

- テスト名は `test_{対象関数}_{説明}` 形式（全体スネークケース、対象関数名と説明はキャメルケース、日本語禁止）になっているか。日本語説明は `@testdox` アノテーションで書いているか。
- Act と Assert を視覚的に分離し、複数項目は `$expected` 配列にまとめて 1 回で検証しているか。
- プリミティブ（int/string/bool/null）・同一インスタンス比較は `assertSame()`、配列・オブジェクトの構造的等価性は `assertEquals()` を使い分けているか。
- 時刻は `Carbon::setTestNow()` / `CarbonImmutable::setTestNow()` で固定し、`now()` 等の現在時刻を直接使っていないか。
- arrange で型付きの共通 Factory / Helper を活用しているか。推論が弱い生成（`factory()->create()` 等）に `@var` で型を補っているか。
- 戻り値型を持つ型付きヘルパー（create 系）直後の `/** @var X $var */` は冗長なので削除しているか。一方 `X::factory()->create(...)` 直前の `@var` は factory の型推論が弱いため維持しているか。
- 単一テストクラスでしか使わないテスト専用ヘルパーを、広く共有される共通 Helper クラスに足していないか。そのテストクラス内の private メソッドとして実装し、共有 Helper の汚染を避けてカプセル化しているか（複数クラスで再利用する場合のみ共通 Helper に置く）。
- 情報配置の四分割原則（CLAUDE.md 参照）: テストは What（仕様・振る舞い）を担う。契約はテスト名（`@testdox` 含む）とケース定義で表現し、テストが仕様書として読める状態にしているか。テスト名やケースで表すべき振る舞いをコメントで補っていないか。

Report only concrete test-readability or correctness risks.

## Focus B: Test Strategy

Review テスト戦略（何をどこまでテストするか）.

- モックは外部依存（外部 API / ファイル / メール / 決済）のみ。同一アプリ内のサービス・Eloquent・内部ビジネスロジックをモックしていないか。
- 単体テストに実 API / 実 DB を叩く分岐（`if (env('USE_REAL_API'))` 等）を入れていないか。実 API テストは `tests/Integration/` に別クラスで分離されているか。
- 内部実装（特定メソッドが呼ばれたか）でなく、振る舞い（戻り値・DB 状態変化・外部 API 呼び出し）を検証しているか。
- ハッピーパス以外（エラー系・境界値: ページ境界・日時範囲・空リスト・上限値）のケースがあるか。ロジック（条件分岐・計算・変換）を持つ関数、entity / value object のメソッドにテストがあるか（単純な getter/mapping は不要）。

Report only concrete test-strategy gaps, not a demand for blanket coverage.

## Focus C: Test Quality

Review テスト品質（偽陰性・偽陽性の排除・データ安全性）.

- DB テストは `DatabaseTransactions` を優先しているか（`RefreshDatabase` は避ける）。DB 書き込みは `assertDatabaseHas` で検証しているか。`assertDatabaseHas` / `assertDatabaseMissing` の第1引数はテーブル名文字列でなく対応する `Model::class` を渡しているか（IDE 補完・リネーム追従。対応モデルが存在する場合のみ）。レコードが存在しないことの検証は `assertDatabaseMissing` を使っているか。
- JSON レスポンスの検証は `assertJson` でなく `assertExactJson` を使い、フィールドの過不足を検知しているか。
- 偽陰性の排除: 期待値・テストデータにゼロ値（`0`/`""`/`false`/`nil`）を使っていないか（初期化漏れと区別がつかない。`42`/`"test_value"` を使う）。integration test のテストデータにプロダクションコードの定数を使わず文字列リテラル直書きにしているか。
- 偽陽性の排除: `assertNotNull`/`assertNotEmpty`/`Len` だけで済ませず具体値で assert しているか。assert 粒度がテスト対象に関係するフィールドに絞られているか（全フィールド厳密 assert は偽陽性、粗すぎは見逃し）。
- テストデータの安全性: 電話番号は実在し得ない未割り当て帯（日本の携帯なら `090-0000-xxxx` 帯）、メールは `example.com` を使い、特定人物の名前・メールを埋め込んでいないか。

Report only concrete test-quality risks that could let bugs pass or cause flakiness.
