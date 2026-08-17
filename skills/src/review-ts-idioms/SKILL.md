---
name: review-ts-idioms
description: Reviews TypeScript / Vue / Nuxt / React / Next frontend diffs for type safety (any avoidance, unknown/generics, runtime validation of API responses, casts hiding future type changes, optional-prop and fallback misuse), type organization/idioms (shared type definitions, discriminated unions, non-null assertion abuse, IDs-as-keys, i18n key parity), and styling/markup discipline (design tokens over arbitrary values, spacing ownership, design-system components, accessible semantic markup). Use when the user asks for TypeScript type-safety review, frontend idiom review, styling/a11y review, or says 「TS の型安全性を見て」「any をチェック」「型定義をレビュー」「デザインシステム/styling を見て」; reports findings only and never edits code.
allowed-tools: [Bash, Read, Grep, Glob, Agent]
---

# /review-ts-idioms

Review TypeScript / Vue / React frontend changes against `<base>...HEAD` using three independent focused subagents (type safety, type organization/idioms, styling & markup discipline). This is review-only: do not modify files.

## Input

- `--base=<branch>`: optional. Resolution is delegated to `skill-resolve-diff` (`origin/master`, falling back to `origin/main`).

## Scope

In scope:
- `any` avoidance, `unknown`/generics, and runtime validation of external data (API responses); casts that hide future type changes; optional-prop and fallback (`?? ""`) misuse
- shared type organization, discriminated unions, and TypeScript idioms; IDs-as-keys; i18n key/punctuation parity
- styling & markup discipline: design tokens over arbitrary values, components owning no external margin, design-system components over raw markup, accessible semantic HTML

Out of scope:
- code edits
- component responsibility and structure: use `review-ts-architecture`
- state management and effects: use `review-ts-state`
- rendering/load performance: use `review-ts-performance`
- XSS and input validation: use `review-ts-security`
- tests: use `review-ts-test`

## Workflow

1. Resolve the review scope:

```bash
skill-resolve-diff --base <base> -- '*.ts' '*.tsx' '*.js' '*.jsx' '*.vue'
```

2. Stop with `ブランチ <base> が見つかりません` if the base branch cannot be resolved.
3. Stop with `レビュー対象のフロントエンドファイルがありません` if no frontend files changed.
4. Store `files` as `<TARGET_FILES>` and `diff` as `<DIFF_CONTEXT>`. When `truncated` is true, keep `truncated_files` as `<TRUNCATED_FILES>`, pass it to every subagent, and report the truncation and the dropped file list to the user. Never drop them silently: the cut point moves as commits land, so silent truncation changes review coverage between runs on the same PR.
5. Read `references/focus-blocks.md`. Stop if it cannot be read: report the path and tell the user to run `./install.sh` to re-link the skills. Never review with a partially loaded focus set — "no findings for this focus" and "this focus never ran" are indistinguishable in the output, so a re-review of the same PR would silently drop last run's findings.
6. Dispatch exactly three `general-purpose` subagents in one assistant message, one per focus block. Do not run them sequentially or replace them with inline review. If Agent is unavailable, report that this skill must be invoked directly from the user session and stop.
7. Wait for all three subagents before integrating results.

## Subagent Prompt Shape

Each subagent receives the shared context below plus one focus block from `references/focus-blocks.md`.

```text
あなたは /review-ts-idioms コマンドの1名のレビュー担当です。レビューのみ行い、ファイルは編集しないでください。

対象ファイル:
<TARGET_FILES>

ベースブランチ: <base>

差分:
<DIFF_CONTEXT>

差分本文から切り詰めで落ちたファイル（空なら「なし」）:
<TRUNCATED_FILES>
※ ここに挙がったファイルは差分本文に含まれていない。必ず Read で全文を読むこと。差分に無いことを見落としの理由にしない。ただし削除されたファイルは Read できないため、その場合のみ対象外として扱う。

手順:
1. 差分を読み、変更されたファイルを Read ツールで全文読み取る。
2. Read ツールの実ファイル行番号で指摘する。diff の @@ 行番号は使わない。
3. 渡された focus の観点に厳密に絞る。他観点には触れない。
4. スタイル系はリポジトリ既存の規約に合わせ、規約がない一般原則のみ指摘する。

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

If all three subagents return no findings, say `型安全性・型定義・styling の観点では指摘はありません`.
