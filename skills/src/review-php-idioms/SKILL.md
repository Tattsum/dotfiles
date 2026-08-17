---
name: review-php-idioms
description: PHP / Laravel の差分を、命名・可読性・型安全性（strict_types・型宣言・PHPDoc）・PHP イディオム（empty() 誤用・正規表現・FQCN/use）の観点でレビューするとき。「PHP のイディオムを見て」「型安全性チェック（PHP）」「命名規約レビュー」等で発動。コードは修正せず指摘のみ報告する。
allowed-tools: [Bash, Read, Grep, Glob, Agent]
---

# /review-php-idioms

Review PHP / Laravel changes against `<base>...HEAD` using three independent idiom-focused subagents. This is review-only: do not modify files.

## Input

- `--base=<branch>`: optional. Resolution is delegated to `skill-resolve-diff` (`origin/master`, falling back to `origin/main`).

## Scope

In scope:
- 命名・可読性（汎用語回避・enum 的分岐の網羅性）
- 型安全性（`declare(strict_types=1)` 方針・引数/戻り値の型宣言・PHPDoc の具体型）
- PHP イディオム（`empty()` 誤用・`is_null()`/`??`・正規表現の `\A`/`\z`・`@link`）

Out of scope:
- code edits
- レイヤー責務・トランザクション・クラス構成: use `review-php-architecture`
- DB スキーマ・クエリ性能・N+1: use `review-php-storage`
- テスト: use `review-php-test`
- セキュリティ: use `review-php-security`

## Workflow

1. Resolve the review scope:

```bash
skill-resolve-diff --base <base> -- '*.php'
```

2. Stop with `ブランチ <base> が見つかりません` if the base branch cannot be resolved.
3. Stop with `レビュー対象の PHP ファイルがありません` if no PHP files changed.
4. Store `files` as `<TARGET_FILES>` and `diff` as `<DIFF_CONTEXT>`. When `truncated` is true, keep `truncated_files` as `<TRUNCATED_FILES>`, pass it to every subagent, and report the truncation and the dropped file list to the user. Never drop them silently: the cut point moves as commits land, so silent truncation changes review coverage between runs on the same PR.
5. Read `references/focus-blocks.md`. Stop if it cannot be read: report the path and tell the user to run `./install.sh` to re-link the skills. Never review with a partially loaded focus set — "no findings for this focus" and "this focus never ran" are indistinguishable in the output, so a re-review of the same PR would silently drop last run's findings.
6. Dispatch exactly three `general-purpose` subagents in one assistant message, one per focus block. Do not run them sequentially or replace them with inline review. If Agent is unavailable, report that this skill must be invoked directly from the user session and stop.
7. Wait for all three subagents before integrating results.

## Subagent Prompt Shape

Each subagent receives the shared context below plus one focus block from `references/focus-blocks.md`.

```text
あなたは /review-php-idioms コマンドの1名のレビュー担当です。レビューのみ行い、ファイルは編集しないでください。

対象ファイル:
<TARGET_FILES>

ベースブランチ: <base>

差分:
<DIFF_CONTEXT>

差分本文から切り詰めで落ちたファイル（空なら「なし」）:
<TRUNCATED_FILES>
※ ここに挙がったファイルは差分本文に含まれていない。必ず Read で全文を読むこと。差分に無いことを見落としの理由にしない。ただし削除されたファイルは Read できないため、その場合のみ対象外として扱う。

手順:
1. 差分を読み、変更された PHP ファイルを Read ツールで全文読み取る。
2. Read ツールの実ファイル行番号で指摘する。diff の @@ 行番号は使わない。
3. 渡された focus の観点に厳密に絞る。他観点には触れない。
4. スタイル系（変数名の case 等）はリポジトリ既存の規約に合わせ、規約がない一般原則のみ指摘する。

出力フォーマット:
### [ファイルパス:行番号]
- **観点**: 担当した focus の見出し（`## Focus X: ...`）を逐語でそのまま書く。言い換え・要約・独自の観点名の創作はしない。
- **問題点**: (具体的に何が問題か)
- **Why**: (なぜ修正すべきか)
- **推奨する修正**: (どう修正すべきか)

該当する指摘がない場合は「該当なし」とだけ明記してください。
推測的・スタイルだけの指摘は避け、根拠を示せる具体的な指摘のみ報告してください。
```

## Integration

After all three subagents return:

1. Count findings by focus group.
2. Verify each finding references a file in `<TARGET_FILES>`; separate out-of-scope findings with a warning.
3. Merge only findings with the same file, same line, and the same verbatim focus heading. If a subagent paraphrased its heading, re-derive it from the focus block instead of merging on the paraphrase.
4. Print `合計N件 → 重複統合M件 → リストN-M件`; explain any mismatch.
5. Output a numbered list and then include each finding detail from the subagent output.

If all subagents return no findings, say `イディオム・型安全観点では指摘はありません`.
