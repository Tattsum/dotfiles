---
name: dotfiles-php-laravel-review
description: PHP / Laravel の差分を、5観点（アーキテクチャ・イディオム/型安全・DB/永続化・テスト・セキュリティ）の専任サブエージェントに分担させて並列レビューし、統合した重要度別の指摘リストを報告するとき。コードは修正しない。「PHP のレビューして」「Laravel の差分を見て」「レビューだけして」等で発動。
allowed-tools: [Bash, Read, Grep, Glob, Agent]
---

# /dotfiles-php-laravel-review

PHP / Laravel の `<base>...HEAD` 差分を、5観点を focus 単位に細分した複数のサブエージェントへ並列に分担させてレビューし、統合した指摘リストを出す**オーケストレーター**。レビューのみ行い、ファイルは編集しない。

個別観点だけ見たい場合は、各観点スキル（`review-php-architecture` / `review-php-idioms` / `review-php-storage` / `review-php-test` / `review-php-security`）を直接呼ぶこともできる。

## Input

- `--base=<branch>`: optional. Default: `origin/master`、解決できなければ `origin/main`。

## Workflow

1. レビュー範囲を解決する:

```bash
git rev-parse --verify <base>
git diff --name-only <base>...HEAD -- '*.php' '*.blade.php' 'database/migrations/*'
git diff <base>...HEAD -- '*.php' '*.blade.php' 'database/migrations/*'
```

2. base ブランチが解決できなければ `ブランチ <base> が見つかりません` と伝えて終了。
3. 変更ファイルがなければ `レビュー対象の変更がありません` と伝えて終了。
4. 変更ファイルを `<TARGET_FILES>`、差分を `<DIFF_CONTEXT>` として保持する。差分が約 60,000 文字を超える場合は末尾を `[... truncated ...]` で切り詰める。
5. 5観点ぶんの focus-block 定義を読み込む。各観点スキルの `references/focus-blocks.md` を Read する:

```
~/.claude/skills/review-php-architecture/references/focus-blocks.md
~/.claude/skills/review-php-idioms/references/focus-blocks.md
~/.claude/skills/review-php-storage/references/focus-blocks.md
~/.claude/skills/review-php-test/references/focus-blocks.md
~/.claude/skills/review-php-security/references/focus-blocks.md
```

   上記パスが無ければ Glob で `**/review-php-*/references/focus-blocks.md` を探して読む。1つも見つからなければ、観点スキル未インストールである旨（`make -C skills install-global` を案内）を伝えて終了。

6. 読み込んだ全 focus block（5観点 × 各2 focus = 計10）について、`general-purpose` サブエージェントを**1つのアシスタントメッセージ内で一斉に並列起動**する。1サブエージェント＝1 focus block。逐次実行やインラインレビューで代替しない。Agent が使えない場合は、本スキルはユーザーセッションから直接起動する必要がある旨を伝えて終了。
7. 全サブエージェントの完了を待ってから統合する。

## Subagent Prompt Shape

各サブエージェントには、下記の共有コンテキストと 1 つの focus block を渡す。`<OWNER>` には観点名（architecture / idioms / storage / test / security）を入れる。

```text
あなたは PHP / Laravel コードレビュー（観点: <OWNER>）の1名のレビュー担当です。レビューのみ行い、ファイルは編集しないでください。

対象ファイル:
<TARGET_FILES>

ベースブランチ: <base>

差分:
<DIFF_CONTEXT>

担当する focus:
<FOCUS_BLOCK>

手順:
1. 差分を読み、変更されたファイルを Read ツールで全文読み取る。
2. Read ツールの実ファイル行番号で指摘する。diff の @@ 行番号は使わない。
3. 渡された focus の観点に厳密に絞る。他観点には触れない。
4. スタイル系（変数名の case 等）はリポジトリ既存の規約に合わせ、規約がない一般原則のみ指摘する。

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

全サブエージェントが返ったら:

1. 観点（OWNER）ごとに指摘件数をカウントする。
2. 各指摘が `<TARGET_FILES>` 内のファイルを参照しているか検証し、対象外は警告付きで分離する。
3. 統合は「同一ファイル・同一行・同一観点タイトル」の場合のみ行い、統合時は元の観点名を併記する。
4. `観点別カウント: architecture: N件, idioms: N件, storage: N件, test: N件, security: N件 (合計N件) → 重複統合M件 → リストN-M件` を出力し、差分があれば原因を明記する。
5. まず観点 × 重要度のサマリー表を出力する。各セルは件数。観点に指摘がなければ `0` を入れる。

```markdown
## 📊 レビューサマリー

| 観点 | 🔴 Must | 🟡 Should | 🟢 Nice | 合計 |
|------|--------|-----------|---------|------|
| architecture | 0 | 0 | 0 | 0 |
| idioms       | 0 | 0 | 0 | 0 |
| storage      | 0 | 0 | 0 | 0 |
| test         | 0 | 0 | 0 | 0 |
| security     | 0 | 0 | 0 | 0 |
| **合計**     | 0 | 0 | 0 | 0 |
```

6. サマリー表に続けて、重要度別フォーマットで指摘の詳細を出力する。各指摘に `[ファイルパス:行番号]` と観点名を付ける。

```
## 🔴 Must（必ず修正）
- [path:line] (観点) 問題 → 修正案

## 🟡 Should（できれば修正）
- [path:line] (観点) 問題 → 修正案

## 🟢 Nice to have（提案）
- [path:line] (観点) 提案
```

全観点で指摘がなかった場合は `全観点で PHP / Laravel レビューの指摘はありません` と明記する。
