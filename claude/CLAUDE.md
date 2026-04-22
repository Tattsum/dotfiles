# Claude Code Global Settings

## 役割・スタンス

コードレビューを依頼された場合、**同僚のシニアエンジニアとして厳しく・具体的に**指摘すること。
「問題なさそう」で済ませず、必ず以下のチェックリストに沿って確認する。

---

## コミットメッセージ規約（必須）

エージェントがコミットを作成する場合、コミットメッセージは必ず以下の 4 要素で構成する。

- Emoji（コミットの種類）: ひと目でどんなコミットなのか判断するため
- Title（コミットの概要）: 簡潔にコミット内容を説明するため
- Reason（コミットの理由）: なぜこのコミットが必要なのか説明するため
- Specification（コミットの意図・仕様）: なぜこのようなコミット内容になったのか説明するため

フォーマット（テンプレ）:

```text
<Emoji> <Title>

Reason:
- ...

Specification:
- ...
```

例:

```text
✨ add commit message template rule

Reason:
- エージェントのコミット意図を一貫して残し、レビュー・追跡を容易にするため

Specification:
- 先頭に種別 Emoji を付与し、本文に Reason と Specification を必須セクションとして含める
```

## コードレビュー チェックリスト

### 🏗 レイヤー境界（Clean Architecture）

- [ ] Domain層にインフラ依存（DB・外部API等）が混入していないか
- [ ] UseCase層がHTTPやgRPCの詳細に依存していないか
- [ ] 依存の方向が内側に向いているか（外→内）
- [ ] インターフェースを介さず具象に依存していないか

### ⚠️ エラーハンドリング

- [ ] `err` を無視していないか（`_` で捨てていないか）
- [ ] エラーに適切なコンテキストが付与されているか（`fmt.Errorf("...: %w", err)`）
- [ ] ドメインエラーとインフラエラーが適切に分離されているか
- [ ] エラーがそのままクライアントに露出していないか

### 📛 命名・可読性

- [ ] 変数名・関数名から意図が読み取れるか
- [ ] 省略しすぎていないか（`u` より `user` など）
- [ ] Goなら`MixedCaps`、proto/SQLはチームの命名規則に沿っているか
- [ ] コメントは「何をするか」でなく「なぜそうするか」を説明しているか
- [ ] 関数が単一責任になっているか（長すぎないか）

### 🧪 テスト

- [ ] ハッピーパス以外（エラー系・境界値）のケースがあるか
- [ ] テーブル駆動テストで書かれているか（Go）
- [ ] モックが適切に使われているか
- [ ] テスト名から何をテストしているかわかるか

### 🔒 セキュリティ

- [ ] SQLインジェクションの可能性はないか（プレースホルダを使っているか）
- [ ] 機密情報（トークン・パスワード等）がログに出力されていないか
- [ ] 認証・認可のチェックが漏れていないか
- [ ] 入力値のバリデーションがされているか

### ⚡ パフォーマンス

- [ ] N+1クエリが発生していないか
- [ ] ループ内で不要なDB/API呼び出しをしていないか
- [ ] 不要なメモリアロケーションがないか
- [ ] インデックスが適切に使われるクエリになっているか

---

## 言語・技術別 追加観点

### Go（言語仕様 / Uber Go Style 準拠チェック）

- **前提**
  - [ ] コードレビュー時は必ず公式仕様（[The Go Programming Language Specification](http://go.dev/ref/spec)）と
        [Uber Go Style Guide](https://github.com/uber-go/guide) を頭に置き、疑問があればどちらかに立ち返ること
  - [ ] 「言語仕様に反する実装」「Uber Go Style に明確に反する実装」は Must として指摘する
- **パッケージ / ファイル構成**
  - [ ] 1 パッケージ 1 つの明確な責務になっているか
  - [ ] `main` パッケージにビジネスロジックを置いていないか（wire だけ・起動だけ）
  - [ ] 循環依存が発生していないか
- **命名・公開範囲**
  - [ ] 公開したいものだけ `UpperCamelCase`（export）、それ以外は `lowerCamelCase`（unexport）になっているか
  - [ ] Getter に `Get` を付けていないか（`Name()` で良いか検討）
  - [ ] コンストラクタは `NewXxx` で統一されているか
- **エラーハンドリング**
  - [ ] `if err != nil { ... }` で逐次ハンドリングされているか、`panic` を安易に使っていないか
  - [ ] `fmt.Errorf("context: %w", err)` でラップされているか
  - [ ] `errors.Is` / `errors.As` が適切に使われているか
- **context**
  - [ ] 外部 I/O（DB, HTTP, gRPC など）を行う関数は第一引数 `ctx context.Context` を受け取っているか
  - [ ] `context.Background()` / `context.TODO()` をライブラリ内で新規に作っていないか（呼び出し元から受け取る）
  - [ ] `WithCancel` / `WithTimeout` の `cancel` を `defer cancel()` しているか
- **goroutine / 並行処理**
  - [ ] goroutine 内から外側の変数を安全に扱っているか（データレースなし）
  - [ ] 終了待ちに `sync.WaitGroup` や `errgroup.Group` を使っているか
  - [ ] チャネルはクローズ漏れ・送受信ブロックがないか
- **インターフェース設計**
  - [ ] `interface` は「利用側のパッケージ」に定義されているか
  - [ ] インターフェースは「最小限のメソッド」に絞られているか（fat interface になっていないか）
  - [ ] 実装構造体をそのまま export する必要がないか（コンストラクタ + interface 経由で足りないか）
- **データ構造・パフォーマンス**
  - [ ] スライスは `make([]T, 0, n)` などで capacity を意識して初期化しているか
  - [ ] map のゼロ値利用（`var m map[K]V`）と `make` の違いを理解した使い方になっているか
  - [ ] ポインタ / 値レシーバの選択が妥当か（可変性・コピーコストを考慮しているか）
- **テスト（Go 版）**
  - [ ] テーブル駆動テストでケースが整理されているか
  - [ ] `t.Helper()` やテスト用ヘルパー関数を活用して重複を減らしているか
  - [ ] 並行処理を含むテストで `-race` も通るか
- **YAGNI / Go らしさ**
  - [ ] 早すぎる抽象化（過度な DI コンテナやジェネリクス抽象など）を入れていないか
  - [ ] 標準ライブラリで足りるところはまず標準を使っているか
  - [ ] 「シンプルさ」と「読みやすさ」を優先した実装になっているか

### gRPC / Protobuf

- **スキーマ設計**
  - [ ] フィールド名・型は命名規則に沿っているか（`snake_case` / 意図が伝わる名前か）
  - [ ] フィールド番号は既存と衝突していないか（既存クライアントに影響しないか）
  - [ ] 不要な `oneof` や過度な入れ子構造になっていないか
- **optional / repeated / map の使い分け**
  - [ ] 必須フィールドを後付けしていないか（Breaking Change になっていないか）
  - [ ] コレクションは `repeated` / `map` のどちらが自然か検討されているか
  - [ ] `optional` の意味（未設定とゼロ値）を正しく扱っているか
- **ステータスコード / エラー設計**
  - [ ] ステータスコードは仕様に沿っているか（`NotFound` / `InvalidArgument` / `AlreadyExists` など）
  - [ ] `details`（エラー詳細）を使う場合、クライアントが扱いやすい構造になっているか
  - [ ] リトライ可能なエラーとそうでないものの区別がつくか
- **API 境界**
  - [ ] gRPC の Request/Response でドメイン層をそのまま漏らしていないか
  - [ ] 将来の拡張余地（予測しすぎない範囲での拡張性）があるか

### SQL / DB

- トランザクション境界は適切か
- NULL許容カラムの扱いは適切か
- マイグレーションは後退可能か（ロールバックできるか）
- インデックスが効くWHERE句になっているか

### TypeScript / Vue / Nuxt / React / Next

- **型設計**
  - [ ] `any` を安易に使っていないか（`unknown` / ジェネリクス / 明示的な型定義で表現できないか）
  - [ ] API レスポンスやドメインオブジェクトに型が付いているか（`zod` / `io-ts` 等でのバリデーションも含めて検討されているか）
  - [ ] 型の重複を避けるための共通定義（`types/`, `@/types` など）が整理されているか
- **コンポーネント設計**
  - [ ] コンポーネントの責務が単一か（Container / Presentational の分離などが必要か）
  - [ ] Props が肥大化していないか（必要であれば分割・カスタムフック化されているか）
  - [ ] 再利用可能な UI / ロジックが適切に抽出されているか
- **状態管理 / 副作用**
  - [ ] React の `useEffect` / Vue のウォッチャ等の依存配列・依存関係が正しいか
  - [ ] グローバルステート（Redux, Zustand, Pinia, Vuex 等）の使用範囲が適切か（局所状態で十分な箇所にまで広げていないか）
  - [ ] 非同期処理（fetch / axios 等）のエラーハンドリング・ローディング状態が適切か
- **セキュリティ / UX**
  - [ ] XSS / CSRF の考慮がされているか（`v-html` / `dangerouslySetInnerHTML` の利用には特に注意）
  - [ ] フォーム入力値のバリデーション（クライアントサイド + サーバサイド）が実装されているか
  - [ ] 不要な再レンダリングや重い計算をメインスレッドで行っていないか（メモ化 / 分割 / 遅延読み込み等）

### PHP / Laravel（言語仕様 / Laravel 流儀 準拠チェック）

- **前提**
  - [ ] PHP の言語仕様・標準ライブラリに沿って実装されているか（[PHP Manual](https://www.php.net/manual/)）
  - [ ] Laravel の公式ドキュメントに沿って実装されているか（[Laravel Docs](https://laravel.com/docs)）
  - [ ] コーディングスタイルは PSR-12 を前提に一貫しているか（[PSR-12](https://www.php-fig.org/psr/psr-12/)）
- **型 / 例外 / エラー設計**
  - [ ] `declare(strict_types=1);` の方針がプロジェクトとして統一されているか（有無・適用範囲）
  - [ ] 引数・戻り値の型宣言が適切か（PHPDoc 依存になりすぎていないか）
  - [ ] 例外に機密情報を含めていないか（SQL、トークン、個人情報など）
  - [ ] 例外の粒度が適切か（握りつぶし・過剰な catch-all をしていないか）
- **Laravel の責務分離**
  - [ ] Controller が肥大化していないか（UseCase/Service への切り出しが必要か）
  - [ ] Eloquent Model にビジネスロジックを詰め込みすぎていないか
  - [ ] FormRequest を使うべき入力検証が controller 内に散らばっていないか
  - [ ] トランザクション境界が適切か（`DB::transaction()` の使い方）
- **セキュリティ**
  - [ ] Mass assignment のガード（`$fillable` / `$guarded`）が適切か
  - [ ] 認証・認可（Policies / Gates / Middleware）の漏れがないか
  - [ ] Blade / フロントへの出力でエスケープが保証されているか
  - [ ] ログに機密情報を出していないか
- **パフォーマンス**
  - [ ] N+1 がないか（`with()` / `load()` 等で解消されているか）
  - [ ] 重い処理を同期リクエストに押し込んでいないか（Queue/Job 化の検討）
  - [ ] コレクション操作でメモリを食い潰していないか（`chunk()` / `cursor()` / pagination）

### データベース設計ルール（レビューガイド）

このドキュメントは、データベース設計に関するコードレビューのガイドラインです。

- **テーブル構成の確認（task コマンド）**
  - **全テーブル一覧の表示**
    - `task db:list-tables`
    - crm データベース内の全テーブル一覧を表示
    - テーブル名を確認してから `db:show-table` を使用する際に便利
  - **特定テーブルの定義表示**
    - `task db:show-table -- <テーブル名>`
    - 指定したテーブルの CREATE TABLE 文を表示
    - 使用例:

```bash
task db:show-table -- members
task db:show-table -- clients
```

- **外部キー制約**
  - [ ] ❌ 原則設定しない
  - **理由**: 外部キー制約は暗黙的な共有ロックを取り、deadlock の要因になる
- **インデックス / 制約の命名**
  - [ ] ✅ 推奨: インデックス名や制約名は明示的に指定せず、Laravel の自動命名に任せる
  - [ ] ⚠️ 例外: MySQL の制約（64 文字制限）に引っかかる場合のみ、手動で短縮した名前を指定する
- **主キー**
  - [ ] ✅ 必須: テーブルの主キーは常に整数型（BIGINT or INT）の `id` とする
  - [ ] ⚠️ 例外: パーティションテーブルでは、`char(36)`（例：`client_id`）や `datetime` 型を複合主キーに含めることを許容する
  - **理由**: MySQL の技術的制約として、パーティションキーは PRIMARY KEY または UNIQUE KEY に含まれている必要がある

例:

```php
// ✅ 推奨: 主キーはBIGINT型のid
Schema::create('member_rank_lower_limits', function (Blueprint $table) {
    $table->id();  // BIGINT型の主キー
    $table->string('client_id');
    $table->integer('rank_id');
    $table->timestamps();
});
```

```php
// ❌ 避ける: 複合主キー
Schema::create('member_rank_lower_limits', function (Blueprint $table) {
    $table->string('client_id');
    $table->integer('rank_id');
    $table->primary(['client_id', 'rank_id']);  // 避ける
    $table->timestamps();
});
```

```sql
-- ✅ 許容: パーティションテーブルの複合主キー（パーティションキーを含める）
CREATE TABLE `member_coupon2_usage_histories` (
    `id` bigint unsigned AUTO_INCREMENT,
    `client_id` char(36) NOT NULL,
    `used_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`, `client_id`, `used_at`),
    ...
)
PARTITION BY RANGE (YEAR(used_at))
SUBPARTITION BY KEY (client_id)
SUBPARTITIONS 16;
```

### テストコードのレビュールール（PHPUnit / Laravel）

このドキュメントは、テストコードに関するコードレビューのガイドラインです。

- **テスト関数命名規約**
  - [ ] ✅ 必須: `test_{対象関数の名前}_{説明}` の形式
  - [ ] ✅ 必須: 全体はスネークケース
  - [ ] ✅ 必須: `{対象関数の名前}` と `{説明}` の部分は英語のキャメルケース
  - [ ] ❌ 禁止: 日本語の使用
  - [ ] ✅ 必須: `@testdox` アノテーションで日本語説明を書く

例:

```php
/**
 * @testdox 有効なSKUでクライアント解析が正常に動作する
 */
public function test_parseClients_withValidSku(): void
{
    // テスト実装
}
```

- **テスト構造**
  - [ ] Act & Assert を分離して読みやすくする

```php
// Act
$actual = SomeService::getData($client);

// Assert
$expected = [
    'client_id' => $client->id,
    'trigger_id' => $trigger->id,
    'title' => 'test',
];
$this->assertEquals($expected, $actual);
```

- **アサーションの使い分け**
  - [ ] 厳密な型チェックが可能な場合は、`assertEquals()` ではなく `assertSame()` を使う
  - **指針**
    - `assertSame()`: プリミティブ（int/string/bool/null）や同一インスタンス比較
    - `assertEquals()`: 配列・オブジェクトの構造的等価性（再帰比較）

```php
$this->assertSame(123, $actual);
$this->assertSame('test', $actual);
$this->assertSame(true, $actual);
```

```php
$expected_array = ['a' => 1, 'b' => 2];
$this->assertEquals($expected_array, $actual_array);
```

- **TestHelper の活用**
  - [ ] `$client`, `$staff`, `$member` を arrange で作る場合は TestHelper を検討する（型が付き linter/補完が向上）
  - 利用可能なメソッド例:
    - `TestHelper::createClient(array $args = []): Client`
    - `TestHelper::createMember(array $params): Member`
    - `TestHelper::createClientStaff(array $args = []): array`（`[Client, Staff]`）

```php
// Arrange
$client = TestHelper::createClient(['name' => 'Test Client']);
$member = TestHelper::createMember(['client_id' => $client->id]);
```

- **DatabaseTransactions**
  - [ ] ✅ 優先: `use DatabaseTransactions;`
  - [ ] ❌ 制限: `RefreshDatabase` はできるだけ避ける

```php
use Illuminate\Foundation\Testing\DatabaseTransactions;

class SomeServiceTest extends TestCase
{
    use DatabaseTransactions;
}
```

- **時刻のモック**
  - [ ] ✅ 必須: `Carbon::setTestNow(...)` または `CarbonImmutable::setTestNow(...)`
  - [ ] ❌ 禁止: 現在時刻の直接使用（`now()` など）

```php
Carbon::setTestNow('2006-01-02 15:04:05');
```

- **モック使用の制限**
  - [ ] ✅ 許可: 外部 API / ファイルシステム / メール送信 / 決済 API
  - [ ] ❌ 避ける: 同一アプリケーション内のサービスクラス / Eloquent / 内部ビジネスロジック

```php
// ✅ 推奨: 外部APIのモック
$mock = $this->mock(StripeApiClient::class);
$mock->shouldReceive('charge')->andReturn(['status' => 'success']);
```

- **assertDatabaseHas**
  - [ ] DB 書き込みをテストする場合は積極的に使用する

```php
$this->assertDatabaseHas('point_events', [
    'client_id' => $client->id,
    'member_id' => 'test-member-1',
    'event_type' => 'earned',
]);
```

- **PHPDoc 型注釈**
  - [ ] Factory 等で推論が弱い場合は `@var` を補う

```php
/** @var Trigger $trigger */
$trigger = Trigger::factory()->create(['client_id' => $client->id]);
```

---

## レビュー時の出力フォーマット

指摘は以下の形式で行う：

```markdown
## 🔴 Must（必ず修正）
- [ファイル名:行番号] 問題の説明 → 修正案

## 🟡 Should（できれば修正）
- [ファイル名:行番号] 問題の説明 → 修正案

## 🟢 Nice to have（提案）
- [ファイル名:行番号] 提案内容
```
