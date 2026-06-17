# Storage Focus Blocks

Use one block per subagent. Keep each subagent constrained to its assigned block.

## Focus A: Migration And Schema Design

Review マイグレーション・スキーマ設計.

- 外部キー制約は原則付けない（暗黙の共有ロックによる deadlock 回避。整合性はアプリ層で担保）。`ON DELETE CASCADE` を避け、削除はアプリから明示しているか。
- 主キーは整数型（BIGINT / INT）の Auto Increment な `id`（UUID を id にするのはアンチパターン）。パーティションテーブルのみ、パーティションキーを含む複合主キーを許容。
- インデックス/制約名はフレームワークの自動命名に任せる（MySQL 64 文字制限に当たる場合のみ手動短縮）。新テーブル名は既存同種テーブルの命名パターンに揃っているか。
- 全マイグレーションに `down()` を実装する。`nullable(false)` 化を戻す `down()` は NULL データのクリーニング手順も書く（後退可能か）。
- 文字コードは `utf8mb4` ＋適切な COLLATE（`utf8` / `utf8mb3` は不可）。判定: 濁点区別不要→`utf8mb4_0900_ai_ci` / 多言語重要→`utf8mb4_unicode_ci` / それ以外→`utf8mb4_general_ci`。大小区別不要なカラムに `utf8mb4_bin` を使っていないか。
- 固定長でない文字列は `VARCHAR(255)`、固定長不変値（UUID 等）のみ `CHAR(36)`。時刻は `DATETIME`（`TIMESTAMP` は 2038 年問題で不可）、`created_at`/`updated_at` は `CURRENT_TIMESTAMP` / `ON UPDATE CURRENT_TIMESTAMP` の定型。
- 既知の値が必ず入るカラムは `NOT NULL` ＋デフォルト。アプリから明示的に入れる値に不要な DEFAULT を設定していないか。JSON 配列の DEFAULT は `[]` か。ライフサイクル status は ENUM / CHECK 制約を検討しているか。

Report only concrete schema risks visible in the changed migrations.

## Focus B: Query Performance And Robustness

Review クエリ性能・堅牢性.

- for ループ内で DB クエリ / 外部 API を呼ぶ N+1 になっていないか（`with()` / `load()` の eager load や `whereIn` 一括取得で解消）。
- slice / 配列を IN 句に渡す箇所で `count == 0` のガードがあるか（空配列は SQL エラー / 全件マッチの温床）。
- 大量データを一度にメモリへ載せていないか（`chunk()` / `cursor()` / pagination の利用）。
- WHERE / JOIN のカラムにインデックスがあるか。複合インデックスはカーディナリティの高いカラムを先頭にしているか。
- 重い処理を同期リクエストに押し込んでいないか（Queue / Job 化の検討）。
- 外部 API / DB の retry は固定間隔でなく exponential backoff か。キャッシュ TTL が必要以上に長くないか。
- 常に取得する必要がないデータを、フラグ・条件を確認する前に全件取得していないか（取得後フィルタで無駄な DB / API アクセスを発生させていないか）。

Report only concrete performance or robustness risks, not speculative tuning.
