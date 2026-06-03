# Claude Code Global Settings

## 役割・スタンス

コードレビューを依頼された場合、**同僚のシニアエンジニアとして厳しく・具体的に**指摘すること。
「問題なさそう」で済ませず、必ず以下のチェックリストに沿って確認する。

### YAGNI 原則（必須）

- 「将来こうなるかもしれない」という理由だけで、**現時点で呼ばれないコード・到達不能なパス・汎用化**を提案しない
- 拡張性の提案は「**今のコードで対応できない具体的なユースケースがすでに存在する**」場合に限る
- `interface` の追加・`switch` の汎化・抽象クラスの導入などは、その必要性を具体的な根拠とともに示せない限り提案しない

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

### バックエンド（Go + Clean Architecture + gRPC）追加レビュー観点

handler / usecase / entity（domain）/ infrastructure のレイヤー構成を持つ Go バックエンドを対象とした実務的なレビュー観点。

- **レイヤー境界・責務（Clean Architecture）**
  - [ ] handler 層にビジネスロジック（条件分岐・フィルタリング・計算）が混在していないか。handler は転送形式↔ドメインのマッピング、usecase はビジネスロジック組み立て、entity はドメインの振る舞いに徹しているか
  - [ ] usecase / entity 層が転送層の型（protobuf 等）を直接参照していないか
  - [ ] ドメイン知識が本来所属する package に書かれているか（例: あるユーザーの未公開記事一覧の取得ロジックは user 側ではなく記事ドメイン側に置く）
  - [ ] 腐敗防止層: 外部 API（決済・外部サービス等）の型・概念を usecase / entity に持ち込まず、infrastructure 層でドメイン型へマッピングしているか
  - [ ] エラーの gRPC ステータスコードへの変換は handler 層で行っているか（`status.Error(codes.XXX, ...)` を usecase / repository で返すと、CLI・バッチ等から再利用できなくなる）
  - [ ] 意味的に正しいサービスメソッドを呼んでいるか（存在確認に一覧取得の件数を見るのではなく、単体取得の NotFound を使う等）

- **コード設計・YAGNI（レイヤーで適用度を変える）**
  - [ ] application 層（handler / usecase）は変更コストが低いので「今必要なコードのみ」。一方 gRPC 定義・DB スキーマは変更コストが高い（クライアント影響・マイグレーション）ため将来の拡張を見越した設計を許容する
  - [ ] ユースケース上通り得ない条件のチェック・防御的コードを書いていないか（上流で保証済みの条件を再チェックしていないか）
  - [ ] 既存の処理・ユーティリティで代替できる新規実装になっていないか
  - [ ] 単一責任（SRP）で関数が分離されているか。複雑なフィルタリング等は共通関数に切り出し、複数箇所での不整合を防いでいるか

- **不要コード検出**
  - [ ] 今回の変更で不要になった関数・const・引数が残っていないか
  - [ ] `return err` している箇所で `log.Errorf` を重複して呼んでいないか（エラーを共通のミドルウェア層で出力する設計なら個別ログはノイズになる）
  - [ ] 常に取得する必要がないデータは、フラグ・条件を先に確認してから取得しているか（全件取得後フィルタで不要な DB / API アクセスを発生させていないか）

- **Go イディオム・型安全性**
  - [ ] struct は原則 pointer で受け渡し（戻り値・レシーバとも）。ただし value object（immutable）は値型で定義しているか
  - [ ] optional 表現: primitive 型は `*string` / `*int32` のようにポインタで nil を表現しているか（値型の optional ラッパーは過剰になりやすい）
  - [ ] nil と 0（ゼロ値）を区別しないフィールドに pointer / optional を使っていないか（例: offset）
  - [ ] nil になり得ないフィールドに nil チェックを書いていないか。逆に nil になり得るなら optional で定義しているか
  - [ ] 早期 return している if の後に `else` を続けていないか
  - [ ] 外部入力の文字列→整数変換で `strconv.Atoi`（32bit オーバーフロー懸念）を避け、`strconv.ParseInt` で bit 数を明示しているか
  - [ ] package スコープの型・変数名が広すぎないか（`Option`→`OrderOption` のように `package名.型名` で読んで意味が通るか）
  - [ ] エラー判定に `err.Error()` の文字列比較や `strings.Contains` を使わず、sentinel error / カスタムエラー型 + `errors.Is` / `errors.As` で判定しているか
  - [ ] slice 初期化で cap が事前に分かるなら `make([]T, 0, len(items))` で指定しているか（根拠のない倍数 `len(x)*2` 等は使わない）

- **命名・関数設計**
  - [ ] 関数名と実処理に乖離がないか（取得+加工は `fetch`/`get` でなく `resolve`/`load`。フィルタを含む `ListXxx` は `xxx.FilterActive()` 併用か `ListActiveXxx` を用意）
  - [ ] `buildXXX` がデータ取得まで行っていないか（取得は呼び出し元で行い build に渡す）
  - [ ] 特定ファイルでしか使わないヘルパーは package 関数でなくレシーバメソッドにしているか（複数ファイル共用なら package 関数のまま）
  - [ ] 命名規約: 見つからなければ error なら `Get`、error を返さず optional/nil/zero を返すなら `Find`。`FindFirstByXXX` のような冗長命名を避けているか
  - [ ] 複数箇所で参照する文字列を const 化しているか（1 箇所のみなら直書きの方が可読）
  - [ ] 変数を使用ブロック内で定義しスコープを最小化しているか
  - [ ] ファイル名とその中のメイン型名を一致させているか
  - [ ] repository の関数名はシンプルに保っているか（`Exists` を足さず `Find`/`Get` で代用、更新系は `Create`/`Update` 程度に留める）
  - [ ] 複数アイテムを返す関数に `List` プレフィックスを使っているか（`GetXxxs` でなく `ListXxx`、`FetchAll`/`FindMany` を避ける）

- **DB 設計（マイグレーション）**
  - [ ] 固定長でない文字列カラムは `VARCHAR(255)`（外部生成の ID 等）。固定長不変値（UUID 等）のみ `CHAR(36)` か
  - [ ] 新テーブル名が既存同種テーブルの命名パターンに揃っているか
  - [ ] ライフサイクルの status カラムは ENUM / CHECK 制約を検討しているか（説明的・カジュアル変更される値は VARCHAR が適切）
  - [ ] 種別が異なるもの（例: コンテンツへの通報とユーザーへの通報）を 1 テーブルで管理し、type により他カラムの意味が変わる設計になっていないか
  - [ ] `ON DELETE CASCADE` を使わず application 側で明示削除しているか（削除タイミングをコードから追跡できるように）
  - [ ] application から明示的に入れる値に不要な DEFAULT を設定していないか。NULL が入り得ないなら NOT NULL、JSON 配列の DEFAULT は `[]` か
  - [ ] CHARSET は `utf8mb4`（`utf8` / `utf8mb3` は不可）。COLLATE は判定フロー（濁点区別不要→`utf8mb4_0900_ai_ci` / 多言語重要→`utf8mb4_unicode_ci` / それ以外→`utf8mb4_general_ci`）で選択。大小区別不要なカラムに `utf8mb4_bin` を使っていないか
  - [ ] slice を IN 句に渡す関数で `len == 0` のガードがあるか（空 slice は SQL エラー）
  - [ ] 時間系カラムは `DATETIME`（`TIMESTAMP` は 2038 年問題で不可）。`created_at` / `updated_at` は `DEFAULT CURRENT_TIMESTAMP` / `ON UPDATE CURRENT_TIMESTAMP` の定型で定義しているか

- **パフォーマンス・堅牢性**
  - [ ] 外部 API / DB の retry は固定間隔でなく exponential backoff か
  - [ ] キャッシュ TTL が必要以上に長くないか（古いデータが返り続ける副作用を避け、効果が得られる最低限に）
  - [ ] URL の処理に `strings.Cut`/`Split` でなく `url.Parse` / `url.URL` を使っているか
  - [ ] 外部値を URL パラメータに埋め込む際 `url.QueryEscape` でエスケープしているか
  - [ ] WHERE / JOIN のカラムにインデックスがあるか。複合インデックスはカーディナリティの高いカラムを先頭にしているか
  - [ ] for ループ内で DB クエリ / 外部 API を呼ぶ N+1 になっていないか（`ListByIDs` 等の一括取得で代替）。protobuf の repeated 生成等でも N+1 が起きていないか
  - [ ] 複数データソースを組み合わせる処理で取得タイミングのズレによる不整合を防御しているか（トランザクション / 取得後の存在確認）

- **テスト戦略**
  - [ ] integration test は setup が重いので、ケースが複数でも setup を 1 回にまとめ、assert を `t.Run` で分けているか。state 依存テストに `t.Parallel()` を使っていないか（flaky の原因）
  - [ ] repository 実装（Get/Create 等）に実 DB アクセスを含むテストがあるか（mock のみで済ませていないか）。テストファイルは実装と同じディレクトリに置いているか
  - [ ] 新規 API エンドポイント（handler）に integration test があるか（handler→usecase→repository の一連を担保）
  - [ ] ロジック（条件分岐・計算・変換）を持つ関数、entity / value object のメソッドにテストがあるか（単純な getter/mapping は不要）

- **テスト品質（偽陰性・偽陽性の排除）**
  - [ ] integration test のテストデータにプロダクションコードの定数を使わず文字列リテラル直書きにしているか（定数値の誤変更を検知するため）
  - [ ] テストデータ・期待値にゼロ値（`0`/`""`/`false`/`nil`）を使っていないか（初期化漏れと区別がつかず偽陰性になる。`42`/`"test_value"` 等を使う）
  - [ ] 各テストがそのレイヤーの責務に絞った検証になっているか（integration は入出力の振る舞い、内部ロジックは unit test）
  - [ ] `assert.NotNil` / `NotEmpty` / `Len` だけで済ませず具体値で assert しているか
  - [ ] integration test の assert 粒度が、テスト対象に関係するフィールドに絞られているか（全フィールド厳密 assert は偽陽性、粗すぎは見逃し）
  - [ ] API レスポンス仕様（フィールド有無・ソート順・ページネーション）がテストに表現され、テストがドキュメントとして機能しているか
  - [ ] 境界値（ページ境界・日時範囲・空リスト・上限値）を意識したテストデータがあるか

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
- **コーディングスタイル**
  - [ ] クラス内定義順が「定数 → プロパティ → コンストラクタ → メソッド」になっているか
  - [ ] FQCN をインラインで記述せず、`use` 文でインポートしているか
  - [ ] 全メソッドに戻り値の型宣言（`: void`, `: string`, `: ?int` 等）が付いているか
  - [ ] Eloquent リレーション（`belongsTo` 等）の第2・3引数は命名規則違反時のみ明示しているか
  - [ ] 正規表現の全体マッチに `^` / `$` ではなく `\A` / `\z` を使っているか（改行抜け穴防止）
  - [ ] PHPDoc 内の外部リンクは URL を直書きせず `@link` タグを使っているか

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

- **ユニットテストとインテグレーションテストの分離**
  - [ ] ❌ 禁止: ユニットテストに実際の外部 API / DB を叩く分岐（`if (env('USE_REAL_API'))` 等）を組み込まない
  - [ ] ✅ 原則: ユニットテストは `Http::fake()` 等のモックのみで完結させる
  - [ ] ✅ 原則: 実 API を叩くテストが必要な場合は `tests/Integration/` に別クラスとして分離する
  - **理由**: 同じコードが CI と手動実行で異なる動作をし再現性が失われる。また `if/else` が Arrange を汚染し、テスト対象が読み取りにくくなる

---

## レビュー前の準備（必須）

コメントを投稿・提案する前に、必ず以下を実施する。

### 1. PR の既存コメントを取得して重複指摘を防ぐ

```bash
# PR のインラインコメントを取得
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments --jq '.[].body'

# PR の全体コメント（会話スレッド）を取得
gh api repos/{owner}/{repo}/issues/{pr_number}/comments --jq '.[].body'
```

- 取得した既存コメントを読み、**すでに議論済み・指摘済みの内容は投稿しない**
- 過去に「対応不要」「意図的」と回答されている指摘は再提起しない
- 同じ観点で別の行に同様の問題がある場合は、まとめて 1 件にする

### 2. 指摘を投稿する前の自己チェック

- [ ] **YAGNI**: 現時点で動く・必要なコードのみを対象にしているか（将来の仮想ユースケースを根拠にしていないか）
- [ ] **重複なし**: 同じ内容を過去のコメントやこの PR のスレッドで既に指摘していないか
- [ ] **根拠あり**: 言語仕様・スタイルガイド・チームの規約・具体的なバグリスクのいずれかを根拠として示せるか

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

---

## GitHub レビューコメント規則（必須）

GitHub でレビューコメントを付けるときは、**必ずコメント先頭にラベルを付ける**。

- **must**: 必ず修正して欲しいと考えている
- **want**: 修正して欲しいと考えている
- **imo**: 自分の意見としては修正した方が良いと感じている（他の人も多分そうかも）
- **imho**: 自分の意見としては修正した方が良いと感じている（他の人は違うかも）
- **nits**: 些細な問題。重箱の隅をつつくレベルだが修正した方が良いかなーと感じてる
- **info**: ただのアドバイスや共有事項。このプルリクエストで修正して欲しいとは思ってないがこれから気をつけるともっと良くなると感じている
- **ask**: 単純に質問。修正して欲しいとは思ってない。意見交換

### インラインコメント運用（必須）

- **すべての指摘・提案・質問は、必ず GitHub の「コード行に紐づくインラインコメント」で行う**（単独の general comment / PR 全体コメントに箇条書きで並べない）
- 例外は、PR の要約や方針共有など **コード行に紐づけられない内容のみ**（この場合でも、指摘そのものはインラインへ分割する）
