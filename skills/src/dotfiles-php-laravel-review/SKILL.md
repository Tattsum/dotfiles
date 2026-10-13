---
name: dotfiles-php-laravel-review
description: PHP / Laravel の差分を、6観点（アーキテクチャ・イディオム/型安全・DB/永続化・テスト・セキュリティ・観測性）の専任サブエージェントに分担させて並列レビューし、統合した重要度別の指摘リストを報告するとき。コードは修正しない。「PHP のレビューして」「Laravel の差分を見て」「レビューだけして」等で発動。
allowed-tools: [Bash, Read, Grep, Glob, Agent]
---

# /dotfiles-php-laravel-review

PHP / Laravel の `<base>...HEAD` 差分を、6観点を focus 単位に細分した複数のサブエージェントへ並列に分担させてレビューし、統合した指摘リストを出す**オーケストレーター**。レビューのみ行い、ファイルは編集しない。

個別観点だけ見たい場合は、各観点スキル（`review-php-architecture` / `review-php-idioms` / `review-php-storage` / `review-php-test` / `review-web-security` / `review-php-observability`）を直接呼ぶこともできる。セキュリティ観点は言語横断の `review-web-security` の focus を読み込む。

## Input

- `--base=<branch>`: optional。解決は `skill-resolve-diff` に委譲する（`origin/master`、無ければ `origin/main`）。
- `--no-cross-review`: optional。指定するとセカンドオピニオン（別エージェントの公式レビュー）を実行しない。`dotfiles-review-and-act` から委譲されたときは必ず付く（PR 全体に対して呼び出し元が 1 回だけ実行するため）。
- `--reachability-context=<path>`: optional。指定するとそのファイルを Read して `<REACHABILITY_CONTEXT>` とし、到達性を自分では解決しない。`dotfiles-review-and-act` から委譲されたときは付く（PR 全体に対して呼び出し元が 1 回だけ解決するため）。読めなければ止めず `未解決（<path> が読めない）` として続行する。会話の文脈ではなくファイルで受け渡すのは、子がインライン Skill でも別コンテキストでも同じに動くため。

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
~/.claude/skills/review-web-security/references/focus-blocks.md
~/.claude/skills/review-php-observability/references/focus-blocks.md
```

   あわせて、security 担当が読む `~/.claude/skills/review-web-security/references/output-discipline.md` と `~/.claude/skills/review-web-security/references/sinks-php.md` が読めることを `test -r` で確認する（本文はサブエージェントが読むので、ここでは Read しない）。配備・サプライチェーン用の `focus-blocks-supply-chain.md` は読み込まない（Dockerfile や CI は `review-web-security --scope=supply-chain` の担当）。

   **上記 8 ファイル（focus-block 6 ＋ security 用の参照 2）のどれか一つでも読めなければ停止する（fail closed）**。読めなかったファイル名を挙げ、`./install.sh` を実行して skill を再配置するよう伝えて終了する。一部だけで続行しない: 「その観点で指摘が0件だった」と「その観点をそもそも実行していない」が出力上区別できず、同じ PR を再レビューしたときに前回の指摘が理由なく消えるため。

   `--no-cross-review` が無ければ `~/.claude/skills/dotfiles-review-and-act/references/cross-review.md` も Read する。読めなくても停止せず、セカンドオピニオンを `未実施（cross-review.md が読めない）` として続行する。focus block の fail closed と扱いを分けるのは、相手エージェントの所見は補助であり、欠けても自分側の観点の網羅性は変わらないため。

   `--reachability-context` が無ければ、次の手順の focus サブエージェント起動より前に、`general-purpose` サブエージェントを 1 体起動し、`~/.claude/skills/review-reachability/SKILL.md` を Read してその手順に従わせ（`--base <base>` を渡す）、返った出力を `<REACHABILITY_CONTEXT>` とする。`SKILL.md` が読めない・サブエージェントが失敗した場合も停止せず、`<REACHABILITY_CONTEXT>` を `未解決（<理由>）` として続行する（全指摘が「到達性: 未確定」になる）。focus block の fail closed と扱いを分けるのは、cross-review と同じく到達性は補助であり、欠けても各観点の網羅性は変わらないため。

6. 各ファイル内の `## Focus ...` ブロックが1サブエージェント分の担当範囲。**読み込めた focus block を実際に数え、その数だけ** `general-purpose` サブエージェントを**1つのアシスタントメッセージ内で一斉に並列起動**する。1サブエージェント＝1 focus block。逐次実行やインラインレビューで代替しない。件数はここに書かず必ず数えること（ハードコードすると focus 追加時にドリフトする）。Agent が使えない場合は、本スキルはユーザーセッションから直接起動する必要がある旨を伝えて終了。
   `--no-cross-review` が無ければ、同じアシスタントメッセージで `cross-review.md` の「起動」に従い `skill-cross-review --from <claude|codex> --base <base>` も起動する。
7. 全サブエージェントとセカンドオピニオンの完了を待つ。
8. 統合の前に、下記「横断チェック」を全体差分に対してオーケストレーター自身で実施し、所見を観点 `横断` として持つ。

## Subagent Prompt Shape

各サブエージェントには、下記の共有コンテキストと 1 つの focus block を渡す。`<OWNER>` には観点名（architecture / idioms / storage / test / security / observability）を入れる。security 担当には、共有プロンプトの末尾に次の指示を足す: 「最初に `~/.claude/skills/review-web-security/references/output-discipline.md` と `~/.claude/skills/review-web-security/references/sinks-php.md` を Read すること。出力は output-discipline.md の出力フォーマット（到達性・既存の公開面・CWE を含む）に従い、共有プロンプトの出力フォーマットと「該当なし」の書き方よりこちらを優先する。focus block の「誤検知の注意」に当たるものは報告しない。」あわせて同じ末尾に、`到達性コンテキスト:` の見出しに続けて `<REACHABILITY_CONTEXT>` を足し、次の 1 行を足す: 「これは差分の所有者側による防御目的のレビュー。攻撃手順・PoC は書かず、欠けている検証と修正の方向で書く（詳細は output-discipline.md）。」到達性コンテキストは security 担当にだけ渡す（到達性は security の重要度にだけ効き、他観点のプロンプトを太らせないため）。

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

各 focus サブエージェントは単一ファイル・単一観点に閉じるため、**PR/差分全体を俯瞰しないと判断できない次の観点はオーケストレーター（あなた）自身が全体差分に対して確認する**。サブエージェントには渡さない（観点をまたいだ重複指摘を避けるため）。所見は観点名 `横断` として統合結果に含める。横断チェックはオーケストレーター自身が1回実施する網羅チェックリストであり、サブエージェントに分散されないため focus の「1 focus 8観点以下」ルールは適用しない（項目が増えたら分割ではなくオーケストレーター自身の負荷で要否を判断する）。

- **整合性 / parity**: 既存の類似実装（sibling リポジトリ・並行する endpoint / 関数・対になる実装）と論理・振る舞いが一致しているか。意図的に異なるなら差分にその根拠があるか。既存の仕様・振る舞いを無言で変更していないか。「すぐ上の関数に合わせるべき」「別リポと揃えるべき」類の乖離を指摘する。
- **diff スコープ / PR 衛生**: 1 PR・1 commit が単一の意味単位に収まっているか。無関係な変更・ついでの修正が混入していないか。純粋なリファクタ/フォーマットとロジック変更が同じ commit に混ざっていないか。混在していれば指摘し、分割を促す。
- **ドキュメントと実装の整合**: リポジトリ内の README・アーキ図・使用例・doc コメントが実装と食い違っていないか。使用例に必須変数が抜けてコピペで失敗する、新規モジュール/機能がトップレベルの構成説明に載っていない、保持世代数など README の記述が実挙動と逆、等。PR 本文・Jira との齟齬は別枠（review-and-act の仕様適合）で見るため、ここではリポジトリ内ドキュメントに絞る。
- **デプロイ前提・データ非互換の明示**: マージしただけでは動かない前提（クライアント登録・契約企業ごとの有効化・リダイレクト URI 追加等）や、既存の発行済み資産が無効になる変更（cookie の開封不能化等）が、PR 説明やマイグレーション手順に明記されているか。未記載なら事故になるため指摘する。
- **マージ順序・中間状態の露出**: 依存する別 PR とのマージ順で、単独マージすると骨格だけ・固定値のまま等の中間状態が本番に露出しないか。インフラだけ先に apply される等の意図が PR 本文に書かれているか。
- **配線の完結性**: 権限やリソースは作られたが、その値がアプリに届いていない状態になっていないか（キューは作られ送信権限も付いたが、URL がアプリの環境変数にも outputs にも渡っておらず送信処理を実装できない等）。片側だけ用意して繋がっていない配線を指摘する。
- **上限値と下位層制約の整合**: アプリ層で設けた上限・件数が、下位層やプラットフォームの制約と整合しているか（条件数の上限より先に CDN の URL 長制限に当たり実効的に機能しない等）。上限が名目だけになっていないか確認する。

## Integration

全サブエージェントが返ったら:

1. 観点（OWNER）ごとに指摘件数をカウントする。横断チェックの所見も観点 `横断` としてカウントに含める。セカンドオピニオンは先に `cross-review.md` の「結果の扱い」で検証・分類し、検証済みで自分側と重複しないものを観点 `second opinion` として含める（実行しなかった場合は 0 件）。
   到達性コンテキストを自分で解決した場合（`--reachability-context` が無かった場合）に exposure findings があれば、観点 `到達性・公開範囲の変更` として含める（無ければ 0 件）。`--reachability-context` で受け取った場合（自分で解決していない場合）は、呼び出し元の `dotfiles-review-and-act` が exposure findings を直接 <FINDINGS> に加えるため、観点別カウント行とサマリー表の `到達性・公開範囲の変更` は `未実行` と書く（0 件と書かない）。
   security 担当の出力に `確認できなかった範囲` 節が無い、またはエラー・拒否文で終わっている場合、その focus を 0 件として数えず「失敗」とする。観点別カウント行とサマリー表の security は、複数の focus 担当を 1 行に集約するため、成功した focus 分の件数に `（失敗: focus X）` を併記し（review-web-security は focus ごとの行なので `失敗` と書く）、`確認できなかった範囲` に `focus X: 出力不完全（再実行を推奨）` を載せる。「該当なし」でも節があれば正常として扱う: 「0 件」と「実行できていない」を出力上区別するため。
2. 各指摘が `<TARGET_FILES>` 内のファイルを参照しているか検証し、対象外は警告付きで分離する。
3. 統合は「同一ファイル・同一行・同一の focus 見出し（逐語一致）」の場合のみ行い、統合時は元の観点名を併記する。サブエージェントが見出しを言い換えていた場合は、言い換えのまま統合せず focus block の見出しに引き直す。ただし観点 `到達性・公開範囲の変更` は focus block ではないので引き直さない（この観点名のまま扱う）。
4. 重複統合の後・反証の前に、security の指摘の重要度を確定する。`重要度案` を採用し、根拠が `output-discipline.md` の軸に沿っていない場合だけ調整して、調整した旨と理由を指摘に注記する。反証には調整後の Must を渡すため、反証より前に行う。
5. 調整後の security の Must 候補（観点 `到達性・公開範囲の変更` を除く）が 1 件以上あれば、`~/.claude/skills/review-web-security/references/must-verification.md` を Read し、その契約で `general-purpose` の反証サブエージェントを 1 体起動して Must 候補をまとめて渡す（`<REACHABILITY_CONTEXT>`・`<TARGET_FILES>`・base も渡す）。判定は次のとおり反映する。以降のカウント・サマリー表・詳細は反映後の重要度で出す。
   - 維持: そのまま。
   - 格下げ: 新しい重要度へ移し、`反証により格下げ（証拠: …）` を注記する。
   - 取り下げ: 指摘リストから外し、`## 🧪 反証で格下げ・取り下げた指摘` に証拠つきで列挙する。黙って消さない。

   Read 失敗・反証サブエージェントの失敗は止めず、Must を維持して `## 🧪 反証で格下げ・取り下げた指摘` の先頭行を `未実施（<理由>）` とする。候補単位で未実施のものは、その Must の詳細行の末尾に `（反証: 未実施・出力不完全）` と注記する。fail closed にしないのは、cross-review と同じく反証は補助であり、欠けても網羅性は変わらないため。
6. `観点別カウント: architecture: N件, idioms: N件, storage: N件, test: N件, security: N件, observability: N件, 横断: N件, 到達性・公開範囲の変更: N件, second opinion: N件 (合計N件) → 重複統合M件 → 反証取り下げK件 → リストN-M-K件` を出力し、差分があれば原因を明記する。以降の出力順は 🌐 到達性コンテキスト → 📊 サマリー → 重要度別の詳細 → 🧪 反証 → 🔁 セカンドオピニオン → 🔍 確認できなかった範囲（security）とする。
7. まず `## 🌐 到達性コンテキスト` として `<REACHABILITY_CONTEXT>` の review-reachability の表をそのまま出す（JSON ブロックは出さない。`未解決` のときはその旨と理由の 1 行）。`--reachability-context` で受け取ったときは表を再掲せず、見出しの下に `呼び出し元（dotfiles-review-and-act）で表示済み` とだけ書く（言語混在 PR で同じ表が言語の数だけ出るのを防ぐため）。自分で解決したときだけ表を出す。続けて観点 × 重要度のサマリー表を出力する。各セルは件数。観点に指摘がなければ `0` を入れる。受け取った到達性コンテキストの `到達性・公開範囲の変更` の行は `未実行` とする。

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
| 到達性・公開範囲の変更 | 0 | 0 | 0 | 0 |
| second opinion | 0 | 0 | 0 | 0 |
| **合計**     | 0 | 0 | 0 | 0 |
```

8. サマリー表に続けて、重要度別フォーマットで指摘の詳細を出力する。各指摘に `[ファイルパス:行番号]` と観点名を付ける。

```
## 🔴 Must（必ず修正）
- [path:line] (観点) 問題 → 修正案

## 🟡 Should（できれば修正）
- [path:line] (観点) 問題 → 修正案

## 🟢 Nice to have（提案）
- [path:line] (観点) 提案
```

   security の指摘の詳細には Source→Sink を併記し、その下に `  - 到達性: … / 既存の公開面: …` の 1 行を足す（値は output-discipline.md の `到達性` と `既存の公開面`）。

9. 重要度別の詳細のあと（`確認できなかった範囲` より前）に、まず `## 🧪 反証で格下げ・取り下げた指摘` を出す。先頭行は固定文言の 3 状態のどれかにする: `対象なし（security の Must 候補 0 件）` / `実施: N 件を検証、格下げ X 件・取り下げ Y 件`（その下に格下げ・取り下げを証拠つきで列挙する） / `未実施（理由）`。続けて `cross-review.md` の「出力」に従って `## 🔁 セカンドオピニオン（<reviewer>）` 枠を出す。実行しなかった・失敗した場合も `未実施（理由）` の 1 行を出す。最後に `## 🔍 確認できなかった範囲（security）` を出し、ここを集約先とする: security 各 focus・反証エージェント・到達性（review-reachability の末尾節。表だけを出し末尾節を捨てない）の「確認できなかった範囲」、失敗 focus の出力不完全、切り詰めの報告を重複を除いてまとめる。

全観点で指摘がなかった場合は `全観点で PHP / Laravel レビューの指摘はありません` と明記し、失敗した focus・反証未実施・到達性未解決・確認できなかった範囲があればその旨を併記し、指摘なしを安全と読ませない。
