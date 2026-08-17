---
name: review-go-storage
description: Reviews Go backend diffs for DB schema design, SQL query performance (indexes, N+1, filter pushdown, empty IN guards, cache), and write-integrity/concurrency/external-I/O robustness (retry backoff, explicit locking over implicit gap locks, incremental persistence, queue ordering/idempotency, bulk atomicity, timing consistency, URL handling). Use when the user asks for DB design review, migration review, SQL performance review, persistence review, concurrency/locking review, external API robustness review, or says 「DBレビュー」「マイグレーション確認」「クエリ性能チェック」「排他制御を見て」; reports findings only and never edits code.
allowed-tools: [Bash, Read, Grep, Glob, Agent]
---

# /review-go-storage

Review Go backend changes against `<base>...HEAD` using three independent storage-focused subagents (schema design, query performance & indexing, write-integrity/concurrency/external-I/O robustness). This is review-only: do not modify files.

## Input

- `--base=<branch>`: optional. Resolution is delegated to `skill-resolve-diff` (`origin/master`, falling back to `origin/main`).

## Scope

In scope:
- DB table and migration design
- query performance: indexes, N+1, filter pushdown, empty `IN` guards, cache TTL
- write integrity, concurrency, and external I/O robustness: retry backoff, explicit locking vs. implicit gap locks, incremental persistence / save-on-error, queue ordering & idempotency, bulk atomicity, multi-source timing consistency, URL parsing/escaping

Out of scope:
- code edits
- architecture and layer responsibility: use `review-go-architecture`
- Go idioms, type safety, and naming: use `review-go-idioms`
- tests: use `review-go-test`

## Workflow

1. Resolve the review scope:

```bash
skill-resolve-diff --base <base> -- '*.go' '*.sql'
```

2. Stop with `ブランチ <base> が見つかりません` if the base branch cannot be resolved.
3. Stop with `レビュー対象の Go/SQL ファイルがありません` if no Go or SQL files changed.
4. Store `files` as `<TARGET_FILES>` and `diff` as `<DIFF_CONTEXT>`. When `truncated` is true, keep `truncated_files` as `<TRUNCATED_FILES>`, pass it to every subagent, and report the truncation and the dropped file list to the user. Never drop them silently: the cut point moves as commits land, so silent truncation changes review coverage between runs on the same PR.
5. Read `references/focus-blocks.md`. Stop if it cannot be read: report the path and tell the user to run `./install.sh` to re-link the skills. Never review with a partially loaded focus set — "no findings for this focus" and "this focus never ran" are indistinguishable in the output, so a re-review of the same PR would silently drop last run's findings.
6. Dispatch exactly three `general-purpose` subagents in one assistant message, one per focus block. Do not run them sequentially or replace them with inline review. If Agent is unavailable, report that this skill must be invoked directly from the user session and stop.
7. Wait for all three subagents before integrating results.

## Subagent Prompt Shape

Each subagent receives the shared context below plus one focus block from `references/focus-blocks.md`.

```text
あなたは /review-go-storage コマンドの1名のレビュー担当です。レビューのみ行い、ファイルは編集しないでください。

対象ファイル:
<TARGET_FILES>

ベースブランチ: <base>

差分 (.go および .sql ファイルの git diff 出力):
<DIFF_CONTEXT>

差分本文から切り詰めで落ちたファイル（空なら「なし」）:
<TRUNCATED_FILES>
※ ここに挙がったファイルは差分本文に含まれていない。必ず Read で全文を読むこと。差分に無いことを見落としの理由にしない。ただし削除されたファイルは Read できないため、その場合のみ対象外として扱う。

手順:
1. 差分を読み、変更された Go ファイル・SQL ファイルを Read ツールで全文読み取る。
2. Read ツールの実ファイル行番号で指摘する。diff の @@ 行番号は使わない。
3. 渡された focus の観点に厳密に絞る。他観点には触れない。

出力フォーマット:
### [ファイルパス:行番号]
- **観点**: 担当した focus の見出し（`## Focus X: ...`）を逐語でそのまま書く。言い換え・要約・独自の観点名の創作はしない。
- **問題点**: (具体的に何が問題か)
- **Why**: (なぜ修正すべきか)
- **推奨する修正**: (どう修正すべきか)

該当する指摘がない場合は「該当なし」とだけ明記してください。
推測的な指摘は避け、根拠を示せる具体的な指摘のみ報告してください。
```

## Integration

After all three subagents return:

1. Count findings by focus group.
2. Verify each finding references a file in `<TARGET_FILES>`; separate out-of-scope findings with a warning.
3. Merge only findings with the same file, same line, and the same verbatim focus heading. If a subagent paraphrased its heading, re-derive it from the focus block instead of merging on the paraphrase.
4. Print `合計N件 → 重複統合M件 → リストN-M件`; explain any mismatch.
5. Output a numbered list and then include each finding detail from the subagent output.

If all three subagents return no findings, say `DB スキーマ・クエリ性能・書込/並行/外部I/O 堅牢性の観点では指摘はありません`.
