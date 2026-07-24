---
name: review-iac
description: Reviews Infrastructure-as-Code diffs (Terraform / OpenTofu `.tf`/`.tfvars`/`.hcl`, and jsonnet/libsonnet config such as ecspresso) for module boundaries and lifecycle separation (splitting resources with different create/update/destroy cadences, isolating out-of-band bootstrap steps) and naming/convention consistency (module, resource, environment, and subdomain naming aligned with existing conventions). Use when the user asks for Terraform review, IaC review, module-structure review, or says 「IaC をレビュー」「Terraform の差分を見て」「module 構成を見て」; reports findings only and never edits code.
allowed-tools: [Bash, Read, Grep, Glob, Agent]
---

# /review-iac

Review Infrastructure-as-Code changes against `<base>...HEAD` using two independent focused subagents (module boundaries & lifecycle, naming & convention consistency). This is review-only: do not modify files.

## Input

- `--base=<branch>`: optional. Default: `origin/master`, falling back to `origin/main`.

## Scope

In scope:
- Terraform / OpenTofu (`.tf`, `.tfvars`, `.hcl`) and jsonnet/libsonnet deploy config (`.jsonnet`, `.libsonnet`, e.g. ecspresso)
- module boundaries and lifecycle separation
- naming and convention consistency for modules, resources, environments, and subdomains

Out of scope:
- code edits
- application code review: use the language-specific `review-*` skills
- generic secret scanning / policy-as-code enforcement (defer to dedicated tooling)

## Workflow

1. Resolve the review scope:

```bash
git rev-parse --verify <base>
git diff --name-only <base>...HEAD -- '*.tf' '*.tfvars' '*.hcl' '*.jsonnet' '*.libsonnet'
git diff <base>...HEAD -- '*.tf' '*.tfvars' '*.hcl' '*.jsonnet' '*.libsonnet'
```

2. Stop with `ブランチ <base> が見つかりません` if the base branch cannot be resolved.
3. Stop with `レビュー対象の IaC ファイルがありません` if no IaC files changed.
4. Store changed files as `<TARGET_FILES>` and the diff as `<DIFF_CONTEXT>`. If the diff exceeds about 60,000 characters, truncate the tail with `[... truncated ...]`.
5. Read `references/focus-blocks.md`.
6. Dispatch exactly two `general-purpose` subagents in one assistant message, one per focus block. Do not run them sequentially or replace them with inline review. If Agent is unavailable, report that this skill must be invoked directly from the user session and stop.
7. Wait for both subagents before integrating results.

## Subagent Prompt Shape

Each subagent receives the shared context below plus one focus block from `references/focus-blocks.md`.

```text
あなたは /review-iac コマンドの1名のレビュー担当です。レビューのみ行い、ファイルは編集しないでください。

対象ファイル:
<TARGET_FILES>

ベースブランチ: <base>

差分:
<DIFF_CONTEXT>

手順:
1. 差分を読み、変更された IaC ファイルを Read ツールで全文読み取る。
2. Read ツールの実ファイル行番号で指摘する。diff の @@ 行番号は使わない。
3. 渡された focus の観点に厳密に絞る。他観点には触れない。
4. スタイル系はリポジトリ既存の規約に合わせ、規約がない一般原則のみ指摘する。

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

If both subagents return no findings, say `IaC のモジュール境界・命名規約の観点では指摘はありません`.
