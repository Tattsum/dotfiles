---
name: dotfiles-php-laravel-review
description: PHP / Laravel の差分を、6観点（アーキテクチャ・イディオム/型安全・DB/永続化・テスト・セキュリティ・観測性）の専任サブエージェントに分担させて並列レビューし、統合した重要度別の指摘リストを報告するとき。コードは修正しない。「PHP のレビューして」「Laravel の差分を見て」「レビューだけして」等で発動。
allowed-tools: [Bash, Read, Grep, Glob, Agent]
---

# /dotfiles-php-laravel-review

PHP / Laravel の `<base>...HEAD` 差分を、6観点を focus 単位に細分した複数のサブエージェントへ並列に分担させてレビューし、統合した指摘リストを出す**オーケストレーター**。レビューのみ行い、ファイルは編集しない。

個別観点だけ見たい場合は、各観点スキル（`review-php-architecture` / `review-php-idioms` / `review-php-storage` / `review-php-test` / `review-php-security` / `review-php-observability`）を直接呼ぶこともできる。

## Input

- `--base=<branch>`: optional。解決は `skill-resolve-diff` に委譲する（`origin/master`、無ければ `origin/main`）。

## Workflow

1. レビュー範囲を解決する:

```bash
skill-resolve-diff --base <base> -- '*.php' '*.blade.php' 'database/migrations/*'
```

2. base ブランチが解決できなければ `ブランチ <base> が見つかりません` と伝えて終了。
3. 変更ファイルがなければ `レビュー対象の変更がありません` と伝えて終了。
4. `files` を `<TARGET_FILES>`、`diff` を `<DIFF_CONTEXT>` として保持する。`truncated` が true のときは `truncated_files` を `<TRUNCATED_FILES>` として保持し、全サブエージェントに渡したうえで、切り詰めが起きた事実と落ちたファイル一覧をユーザーに報告する。黙って落とさない: 切断位置は commit が増えるたびに動くため、同じ PR でも実行ごとにレビュー範囲が変わる。
5. 6観点ぶんの focus-block 定義を読み込む。各観点スキルの `references/focus-blocks.md` を Read する:

```
~/.claude/skills/review-php-architecture/references/focus-blocks.md
~/.claude/skills/review-php-idioms/references/focus-blocks.md
~/.claude/skills/review-php-storage/references/focus-blocks.md
~/.claude/skills/review-php-test/references/focus-blocks.md
~/.claude/skills/review-php-security/references/focus-blocks.md
~/.claude/skills/review-php-observability/references/focus-blocks.md
```

   **6ファイルすべてが読めなければ停止する（fail closed）**。読めなかったファイル名を挙げ、`./install.sh` を実行して skill を再配置するよう伝えて終了する。一部だけで続行しない: 「その観点で指摘が0件だった」と「その観点をそもそも実行していない」が出力上区別できず、同じ PR を再レビューしたときに前回の指摘が理由なく消えるため。

6. 各ファイル内の `## Focus ...` ブロックが1サブエージェント分の担当範囲。**読み込めた focus block を実際に数え、その数だけ** `general-purpose` サブエージェントを**1つのアシスタントメッセージ内で一斉に並列起動**する。1サブエージェント＝1 focus block。逐次実行やインラインレビューで代替しない。件数はここに書かず必ず数えること（ハードコードすると focus 追加時にドリフトする）。Agent が使えない場合は、本スキルはユーザーセッションから直接起動する必要がある旨を伝えて終了。
7. 全サブエージェントの完了を待つ。
8. 統合の前に、下記「横断チェック」を全体差分に対してオーケストレーター自身で実施し、所見を観点 `横断` として持つ。

## Subagent Prompt Shape

各サブエージェントには、下記の共有コンテキストと 1 つの focus block を渡す。`<OWNER>` には観点名（architecture / idioms / storage / test / security / observability）を入れる。

```text
あなたは PHP / Laravel コードレビュー（観点: <OWNER>）の1名のレビュー担当です。レビューのみ行い、ファイルは編集しないでください。

対象ファイル:
<TARGET_FILES>

ベースブランチ: <base>

差分:
<DIFF_CONTEXT>

差分本文から切り詰めで落ちたファイル（空なら「なし」）:
<TRUNCATED_FILES>
※ ここに挙がったファイルは差分本文に含まれていない。必ず Read で全文を読むこと。差分に無いことを見落としの理由にしない。ただし削除されたファイルは Read できないため、その場合のみ対象外として扱う。

担当する focus:
<FOCUS_BLOCK>

手順:
1. 差分を読み、変更されたファイルを Read ツールで全文読み取る。
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

## 横断チェック（オーケストレーター自身が全体差分に対して実施）

各 focus サブエージェントは単一ファイル・単一観点に閉じるため、**PR/差分全体を俯瞰しないと判断できない次の2点はオーケストレーター（あなた）自身が全体差分に対して確認する**。サブエージェントには渡さない（観点をまたいだ重複指摘を避けるため）。所見は観点名 `横断` として統合結果に含める。

- **整合性 / parity**: 既存の類似実装（sibling リポジトリ・並行する endpoint / 関数・対になる実装）と論理・振る舞いが一致しているか。意図的に異なるなら差分にその根拠があるか。既存の仕様・振る舞いを無言で変更していないか。「すぐ上の関数に合わせるべき」「別リポと揃えるべき」類の乖離を指摘する。
- **diff スコープ / PR 衛生**: 1 PR・1 commit が単一の意味単位に収まっているか。無関係な変更・ついでの修正が混入していないか。純粋なリファクタ/フォーマットとロジック変更が同じ commit に混ざっていないか。混在していれば指摘し、分割を促す。

## Integration

全サブエージェントが返ったら:

1. 観点（OWNER）ごとに指摘件数をカウントする。横断チェックの所見も観点 `横断` としてカウントに含める。
2. 各指摘が `<TARGET_FILES>` 内のファイルを参照しているか検証し、対象外は警告付きで分離する。
3. 統合は「同一ファイル・同一行・同一の focus 見出し（逐語一致）」の場合のみ行い、統合時は元の観点名を併記する。サブエージェントが見出しを言い換えていた場合は、言い換えのまま統合せず focus block の見出しに引き直す。
4. `観点別カウント: architecture: N件, idioms: N件, storage: N件, test: N件, security: N件, observability: N件, 横断: N件 (合計N件) → 重複統合M件 → リストN-M件` を出力し、差分があれば原因を明記する。
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
| observability | 0 | 0 | 0 | 0 |
| 横断         | 0 | 0 | 0 | 0 |
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
