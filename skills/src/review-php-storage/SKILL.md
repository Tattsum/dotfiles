---
name: review-php-storage
description: PHP / Laravel の差分を、DB スキーマ設計（マイグレーション・外部キー・主キー・charset/collate・down 実装）とクエリ性能・堅牢性（N+1・空 IN ガード・chunk/cursor・リトライ）の観点でレビューするとき。「DB レビュー（PHP）」「マイグレーション確認」「N+1 チェック」等で発動。コードは修正せず指摘のみ報告する。
allowed-tools: [Bash, Read, Grep, Glob, Agent]
---

# /review-php-storage

Review PHP / Laravel changes against `<base>...HEAD` using two independent persistence-focused subagents. This is review-only: do not modify files.

## Input

- `--base=<branch>`: optional. Default: `origin/master`, falling back to `origin/main`.

## Scope

In scope:
- マイグレーション（外部キー方針・主キー・命名・charset/collate・時刻型・`down()`）
- クエリ性能・堅牢性（N+1・空配列 IN ガード・`chunk()`/`cursor()`・インデックス・リトライ）

Out of scope:
- code edits
- SQL インジェクション等のセキュリティ: use `review-php-security`
- レイヤー責務・トランザクション: use `review-php-architecture`
- 命名・型安全: use `review-php-idioms`
- テスト: use `review-php-test`

## Workflow

1. Resolve the review scope:

```bash
git rev-parse --verify <base>
git diff --name-only <base>...HEAD -- '*.php' 'database/migrations/*'
git diff <base>...HEAD -- '*.php' 'database/migrations/*'
```

2. Stop with `ブランチ <base> が見つかりません` if the base branch cannot be resolved.
3. Stop with `レビュー対象のファイルがありません` if no PHP / migration files changed.
4. Store changed files as `<TARGET_FILES>` and the diff as `<DIFF_CONTEXT>`. If the diff exceeds about 60,000 characters, truncate the tail with `[... truncated ...]`.
5. Read `references/focus-blocks.md`. 既存スキーマを確認する際は `cat` で雑に読まず、マイグレーションファイル / スキーマダンプ / `SHOW CREATE TABLE` 等の正確な定義を参照する。
6. Dispatch exactly two `general-purpose` subagents in one assistant message, one per focus block. Do not run them sequentially or replace them with inline review. If Agent is unavailable, report that this skill must be invoked directly from the user session and stop.
7. Wait for both subagents before integrating results.

## Subagent Prompt Shape

Each subagent receives the shared context below plus one focus block from `references/focus-blocks.md`.

```text
あなたは /review-php-storage コマンドの1名のレビュー担当です。レビューのみ行い、ファイルは編集しないでください。

対象ファイル:
<TARGET_FILES>

ベースブランチ: <base>

差分:
<DIFF_CONTEXT>

手順:
1. 差分を読み、変更されたファイルを Read ツールで全文読み取る。
2. Read ツールの実ファイル行番号で指摘する。diff の @@ 行番号は使わない。
3. 渡された focus の観点に厳密に絞る。他観点には触れない。

出力フォーマット:
### [ファイルパス:行番号]
- **観点**: (focus 内の観点タイトル)
- **問題点**: (具体的に何が問題か)
- **Why**: (なぜ修正すべきか)
- **推奨する修正**: (どう修正すべきか)

該当する指摘がない場合は「該当なし」とだけ明記してください。
推測的・スタイルだけの指摘は避け、根拠を示せる具体的な指摘のみ報告してください。
```

## Integration

After both subagents return:

1. Count findings by focus group.
2. Verify each finding references a file in `<TARGET_FILES>`; separate out-of-scope findings with a warning.
3. Merge only findings with the same file, same line, and same focus title.
4. Print `合計N件 → 重複統合M件 → リストN-M件`; explain any mismatch.
5. Output a numbered list and then include each finding detail from the subagent output.

If all subagents return no findings, say `DB・永続化観点では指摘はありません`.
