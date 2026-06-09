---
name: review-go-test
description: Reviews Yappli Go backend diffs for test strategy, repository tests, integration tests, logic coverage, assertion quality, false negatives, boundary cases, and layer-appropriate verification. Use when the user asks for test review, test-quality review, coverage review, integration-test review, repository-test review, assertion review, or says 「テストをレビュー」「テスト品質チェック」「coverage 観点で見て」; reports findings only and never edits code.
allowed-tools: [Bash, Read, Grep, Glob, Agent]
---

# /review-go-test

Review Yappli Go backend changes against `<base>...HEAD` using two independent test-focused subagents. This is review-only: do not modify files.

## Input

- `--base=<branch>`: optional. Default: `origin/master`.

## Scope

In scope:
- where tests are required and how setup should be structured
- repository tests, API integration tests, and tests for logic-bearing functions
- assertion quality, false-negative prevention, boundary values, and layer-appropriate verification

Out of scope:
- code edits
- architecture and layer responsibility: use `review-go-architecture`
- Go idioms, type safety, and naming: use `review-go-idioms`
- DB schema, query performance, and external I/O: use `review-go-storage`

## Workflow

1. Resolve the review scope:

```bash
git rev-parse --verify <base>
git diff --name-only <base>...HEAD -- '*.go'
git diff <base>...HEAD -- '*.go'
```

2. Stop with `ブランチ <base> が見つかりません` if the base branch cannot be resolved.
3. Stop with `レビュー対象の Go ファイルがありません` if no Go files changed.
4. Store changed files as `<TARGET_FILES>` and the diff as `<DIFF_CONTEXT>`. If the diff exceeds about 60,000 characters, truncate the tail with `[... truncated ...]`.
5. Read `references/focus-blocks.md`.
6. Dispatch exactly two `general-purpose` subagents in one assistant message, one per focus block. Do not run them sequentially or replace them with inline review. If Agent is unavailable, report that this skill must be invoked directly from the user session and stop.
7. Wait for both subagents before integrating results.

## Subagent Prompt Shape

Each subagent receives the shared context below plus one focus block from `references/focus-blocks.md`.

```text
あなたは /review-go-test コマンドの1名のレビュー担当です。レビューのみ行い、ファイルは編集しないでください。

対象ファイル:
<TARGET_FILES>

ベースブランチ: <base>

差分:
<DIFF_CONTEXT>

手順:
1. 差分を読み、変更された Go ファイルを Read ツールで全文読み取る。
2. Read ツールの実ファイル行番号で指摘する。diff の @@ 行番号は使わない。
3. 渡された focus の観点に厳密に絞る。他観点には触れない。

出力フォーマット:
### [ファイルパス:行番号]
- **観点**: (focus 内の観点タイトル)
- **問題点**: (具体的に何が問題か)
- **Why**: (なぜ修正すべきか)
- **推奨する修正**: (どう修正すべきか)

該当する指摘がない場合は「該当なし」とだけ明記してください。
推測的な指摘は避け、根拠を示せる具体的な指摘のみ報告してください。
```

## Integration

After both subagents return:

1. Count findings by focus group.
2. Verify each finding references a file in `<TARGET_FILES>`; separate out-of-scope findings with a warning.
3. Merge only findings with the same file, same line, and same focus title.
4. Print `合計N件 → 重複統合M件 → リストN-M件`; explain any mismatch.
5. Output a numbered list and then include each finding detail from the subagent output.

If both subagents return no findings, say `テスト戦略・テスト品質の観点では指摘はありません`.
