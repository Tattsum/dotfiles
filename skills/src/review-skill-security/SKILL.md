---
name: review-skill-security
description: AI エージェント Skill（SKILL.md・スクリプト等）をインストール前にセキュリティレビューするとき。プロンプトインジェクション・データ窃取・権限昇格・サプライチェーン攻撃・過剰エージェンシー・MCP 汚染など 16 カテゴリ 64 パターンを静的解析し、リスクスコアとともに Must/Should/Info で報告する。外部リポジトリ・URL・ZIP・ローカルディレクトリのいずれにも対応。コードは修正しない。
allowed-tools: [Bash, Read, Grep, Glob, Agent]
---

# /review-skill-security

Install 前に Skill をセキュリティレビューする。**コードは修正しない。報告のみ。**

## Input

- `<path>`: 必須。Git URL / ローカルパス / ファイルパスのいずれか。
  - 例: `https://github.com/user/my-skill`
  - 例: `./skills/src/my-skill/`
  - 例: `./SKILL.md`

## Scope

- SKILL.md（マニフェスト・説明文・トリガー定義）
- Bash / Python / Shell スクリプト
- 設定ファイル（YAML, JSON, TOML）
- 依存定義（pyproject.toml, requirements.txt, package.json）
- YARA / パターン定義ファイル

## Workflow

1. 対象パスを解決する。Git URL なら `git clone --depth=1` でチェックアウト。
2. 対象内の全ファイル一覧を取得する（`find . -type f | head -200`）。
3. SKILL.md が存在する場合は必ず全文読む。
4. `references/focus-blocks.md` を読む。
5. Focus ブロックごとに **4つの `general-purpose` サブエージェント** を同時に起動する（順次実行禁止）。
6. 全サブエージェント完了後に結果を統合する。

## Subagent Prompt Shape

各サブエージェントは以下の共通コンテキスト＋1 Focus ブロックを受け取る。

```text
あなたは /review-skill-security の1名のセキュリティレビュー担当です。コードは編集しないでください。

対象パス: <TARGET_PATH>
ファイル一覧:
<FILE_LIST>

SKILL.md 内容:
<SKILL_MD_CONTENT>

手順:
1. ファイル一覧から渡された Focus カテゴリに関係するファイルを特定し Read ツールで全文読む。
2. 渡された Focus の観点に厳密に絞って検査する。他観点には触れない。
3. Bash で grep 検索を行い証拠を示す（行番号必須）。

出力フォーマット:
### [ファイルパス:行番号] <パターンID>: <パターン名>
- **深刻度**: CRITICAL / HIGH / MEDIUM / LOW
- **証拠**: (該当コード or テキスト抜粋)
- **問題点**: (具体的に何が問題か)
- **推奨対応**: (どう修正すべきか)

該当なしの場合: 「該当なし」とだけ明記する。
推測・過剰報告は避け、具体的証拠を示せる指摘のみ報告する。
```

## Integration

全サブエージェント完了後:

1. 深刻度別にリスクスコアを計算する（CRITICAL=50, HIGH=25, MEDIUM=10, LOW=5）。
2. 実行可能スクリプトが含まれる場合はスコアを 1.3 倍（最大 100 点）。
3. スコアバンド判定:
   - 0–20: 🟢 LOW — インストール可
   - 21–50: 🟡 MEDIUM — 注意してインストール
   - 51–80: 🔴 HIGH — インストール非推奨
   - 81–100: 💀 CRITICAL — インストール禁止
4. 重複（同ファイル同行同パターン）を統合する。
5. 以下の形式で最終レポートを出力する:

```
## Skill セキュリティレビュー結果

**対象**: <path>
**リスクスコア**: XX/100 — <バンド>

### 🔴 Must（必ず対応）
- [ファイル:行] P1: プロンプトインジェクション — 問題点 → 推奨対応

### 🟡 Should（できれば対応）
- ...

### 🟢 Info（確認事項）
- ...

### 統計
- CRITICAL: N件 / HIGH: N件 / MEDIUM: N件 / LOW: N件
- 合計 N件（重複統合後）
```

問題が1件もない場合: `セキュリティ上の指摘はありません（スコア: 0/100）` とだけ明記する。
