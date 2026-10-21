---
name: review-web-security
description: Web アプリの差分を、書籍『Webアプリケーションセキュリティ入門』（yousukezan）準拠の言語横断セキュリティ観点でレビューするとき。コード用の 8 focus（インジェクション / XSS・クライアントサイド / 認証・セッション・CSRF / 認可・API 契約 / 状態・業務ロジック / SSRF・外部 I/O / ファイル / 情報露出・ログ・本番設定）と、Dockerfile・CI workflow・依存 lock が差分にあるときだけ動く配備・サプライチェーン focus を専任サブエージェントで並列実行し、Go / PHP-Laravel / TS の言語別 Sink 表を引きながら Source→Sink 付きの Must / Should / Nice で報告する。コードは修正しない。「セキュリティレビューして」「Web セキュリティを見て」「認可漏れ・SQLi・XSS・SSRF をチェック」「Dockerfile や CI のセキュリティを見て」等で発動。dotfiles-code-review もセキュリティ観点としてこの focus を読み込む。
allowed-tools: [Bash, Read, Grep, Glob, Agent]
---

# /review-web-security

Web アプリの `<base>...HEAD` 差分を、言語に依存しないセキュリティ観点の focus ごとに専任サブエージェントへ分担させてレビューし、統合した指摘リストを出す。レビューのみ行い、ファイルは編集しない。

- 観点の正本は `references/focus-blocks.md`（コード用 A〜H）と `references/focus-blocks-supply-chain.md`（配備・サプライチェーン I）。言語別の危険 API は `references/sinks-go.md` / `sinks-php.md` / `sinks-ts.md`、出力の規律と重要度の軸は `references/output-discipline.md`。
- OWASP MASVS 索引から Web にも適用できる観点を既存 focus に組み込んでいる。MASVS を指定されたレビューや分類・適用範囲を確認するときは [references/owasp-masvs.md](references/owasp-masvs.md) を読む。モバイルアプリの全要件を検証するスキルではなく、このレビューだけで MASVS 適合とは判定しない。
- Claude Code 組み込みの `/security-review` は、確度の高い脆弱性を単発で洗い出す汎用スキャン。本スキルは言語別 Sink 表・書籍準拠の誤検知の注意・Must / Should / Nice を持ち、`dotfiles-code-review` からも読み込まれる常設のレビュー観点という位置づけ。
- メインセッションから起動する。Agent が使えない場合（サブエージェントの中で呼ばれた等）は、インラインの単発レビューで代替せずに停止し、`このスキルはメインセッションから起動してください。実装を担当するサブエージェントは lint/test までを行い、レビューは独立した検証としてメインから起動します` と返す。

## Input

- `--base=<branch>`: optional。解決は `skill-resolve-diff` に委譲する（`origin/master`、無ければ `origin/main`）。

## Scope

対象:
- コード（A〜H）: インジェクション、XSS とクライアントサイド、認証・セッション・CSRF、認可と API 契約、状態と業務ロジック、SSRF と外部 I/O、ファイル、情報露出・ログ・本番設定
- 配備とサプライチェーン（I）: Dockerfile、compose、`.github/workflows/*`、依存の manifest と lock、レジストリ設定

対象外:
- コードの修正
- Terraform / OpenTofu / jsonnet の IaC: `dotfiles-code-review` の iac
- 新規依存を採用するかどうかの判断: `dotfiles-plan-first` の Phase 2
- ログの一般的な品質（コンテキスト・ログレベル）: `dotfiles-code-review` の observability
- AI エージェント Skill 自体のセキュリティ: `review-skill-security`
- レイヤー責務・命名・型安全・DB スキーマ・テスト戦略: `dotfiles-code-review`

## Workflow

`<SKILL_DIR>` はこのスキルのディレクトリの絶対パス（`~/.claude/skills/review-web-security`）とする。以下の参照ファイルはすべて `<SKILL_DIR>` 起点で扱う。相対パスにしないこと: サブエージェントや `test -r` の cwd はレビュー対象のリポジトリなので、`references/...` のままでは存在していても読めず、fail closed が誤って発動する。

1. コードの範囲を解決する:

```bash
skill-resolve-diff --base <base> -- '*.go' '*.php' '*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs' '*.cjs' '*.vue' '*.sql' '*.html' '*.tmpl' '*.gohtml'
```

2. 配備・サプライチェーンの範囲を解決する:

```bash
skill-resolve-diff --base <base> -- '*Dockerfile*' '*.dockerfile' '*compose*.yml' '*compose*.yaml' '.github/workflows/*' '*go.mod' '*go.sum' '*composer.json' '*composer.lock' '*package.json' '*package-lock.json' '*pnpm-lock.yaml' '*yarn.lock' '*.npmrc'
```

3. base ブランチが解決できなければ `ブランチ <base> が見つかりません` と伝えて終了。
4. 解決した範囲のファイルがすべて空なら `レビュー対象のファイルがありません` と伝えて終了する。
5. 範囲ごとに `files` を `<TARGET_FILES>`、`diff` を `<DIFF_CONTEXT>` として保持する。`truncated` が true のときは `truncated_files` を `<TRUNCATED_FILES>` として保持し、その範囲のサブエージェント全員に渡したうえで、切り詰めが起きた事実と落ちたファイル一覧をユーザーに報告する。黙って落とさない: 切断位置は commit が増えるたびに動くため、同じ PR でも実行ごとにレビュー範囲が変わる。
6. コードの範囲の `languages`（go / php / ts）に対応する `<SKILL_DIR>/references/sinks-<lang>.md` を `<SINK_FILES>` とする。該当が無ければ `<SINK_FILES>` は「なし（言語非依存の観点だけで確認する）」とする。
7. 使う focus 定義を Read する。コードのファイルがあれば `<SKILL_DIR>/references/focus-blocks.md`、配備・サプライチェーンのファイルがあれば `<SKILL_DIR>/references/focus-blocks-supply-chain.md`。あわせて `<SKILL_DIR>/references/output-discipline.md` と `<SINK_FILES>` が読めることを `test -r` で確認する（本文はサブエージェントが読む）。**どれか一つでも読めなければ停止する（fail closed）**。読めなかったパスを挙げ、`./install.sh` を実行して skill を再配置するよう伝えて終了する。一部だけで続行しない: 「その focus で指摘が0件だった」と「その focus をそもそも実行していない」が出力上区別できず、同じ PR を再レビューしたときに前回の指摘が理由なく消えるため。
8. コードの範囲にファイルがあれば、focus サブエージェントの起動（次の手順）より前に、`general-purpose` サブエージェントを 1 体起動し、`~/.claude/skills/review-reachability/SKILL.md` を Read してその手順に従わせ（`--base <base>` を渡す）、返った出力を `<REACHABILITY_CONTEXT>` とする。コードの範囲が空なら解決せず `未解決（配備・サプライチェーンだけの差分では解決しない）` とする。`SKILL.md` が読めない・サブエージェントが失敗した場合も停止せず、`<REACHABILITY_CONTEXT>` を `未解決（<理由>）` として続行する（全指摘が「到達性: 未確定」になる）。上記 fail closed の対象に含めないのは、到達性は補助であり、欠けても各 focus の網羅性は変わらないため。
9. 読み込んだファイル内の `## Focus ...` ブロックが1サブエージェント分の担当範囲。**読み込めた focus block を実際に数え、その数だけ** `general-purpose` サブエージェントを**1つのアシスタントメッセージ内で一斉に並列起動**する。コード用の focus にはコードの範囲、focus I には配備・サプライチェーンの範囲を渡す。逐次実行やインラインレビューで代替しない。件数はここに書かず必ず数えること（ハードコードすると focus 追加時にドリフトする）。
10. 全サブエージェントの完了を待つ。

## Subagent Prompt Shape

各サブエージェントには、下記の共有コンテキストと 1 つの focus block を渡す。`<SKILL_DIR>` と `<SINK_FILES>` は Workflow で決めた絶対パスをそのまま入れる。focus I には `<SINK_FILES>` として「なし」を渡す。

```text
あなたは /review-web-security の1名のレビュー担当です。レビューのみ行い、ファイルは編集しないでください。

これは差分の所有者側による防御目的のレビュー。攻撃手順・PoC は書かず、欠けている検証と修正の方向で書く（詳細は output-discipline.md）。

最初に次を Read すること:
- <SKILL_DIR>/references/output-discipline.md（読み方・出力フォーマット・重要度案の付け方）
- 言語別 Sink 表: <SINK_FILES>

対象ファイル:
<TARGET_FILES>

ベースブランチ: <base>

到達性コンテキスト（「未解決」なら、確認できていない統制は無いものとして扱う）:
<REACHABILITY_CONTEXT>

差分:
<DIFF_CONTEXT>

差分本文から切り詰めで落ちたファイル（空なら「なし」）:
<TRUNCATED_FILES>
※ ここに挙がったファイルは差分本文に含まれていない。必ず Read で全文を読むこと。差分に無いことを見落としの理由にしない。ただし削除されたファイルは Read できないため、その場合のみ対象外として扱う。

担当する focus:
<FOCUS_BLOCK>

手順:
1. 差分を読み、変更されたファイルを Read ツールで全文読み取る。Source や Sink が差分の外にあるときは、呼び出し元・呼び出し先も Read してたどる。
2. Read ツールの実ファイル行番号で指摘する。diff の @@ 行番号は使わない。
3. 渡された focus の観点に厳密に絞る。他の focus には触れない。
4. focus block の「誤検知の注意」に当たるものは報告しない。

出力は output-discipline.md の出力フォーマット（到達性・既存の公開面・CWE を含む）に従う。
該当する指摘がない場合は、先頭行を「該当なし」とし、そのあとに「確認できなかった範囲」の節を付けること。
```

## Integration

全サブエージェントが返ったら:

1. focus ごとに指摘件数をカウントする。到達性コンテキストに exposure findings があれば、観点 `到達性・公開範囲の変更` として含める（無ければ 0 件、解決しなかった場合は `未実行`）。
   サブエージェントの出力に `確認できなかった範囲` 節が無い、またはエラー・拒否文で終わっている場合、その focus を 0 件として数えず「失敗」とする。カウント行とサマリー表のその focus の行は `失敗` と書き、`確認できなかった範囲` に `focus X: 出力不完全（再実行を推奨）` を載せる。「該当なし」でも節があれば正常として扱う: 「0 件」と「実行できていない」を出力上区別するため。
2. 各指摘が `<TARGET_FILES>` 内のファイルを参照しているか検証し、対象外は警告付きで分離する。
3. 統合は「同一ファイル・同一行・同一の focus 見出し（逐語一致）」の場合のみ行う。サブエージェントが見出しを言い換えていた場合は、言い換えのまま統合せず focus block の見出しに引き直す。ただし観点 `到達性・公開範囲の変更` は focus block ではないので引き直さない（この観点名のまま扱う）。
4. 重要度はサブエージェントの `重要度案` を採用する。根拠が `output-discipline.md` の軸に沿っていない場合だけ調整し、調整した旨と理由を指摘に注記する。
5. 重複統合と重要度の確定の後・出力の前に、Must 候補（観点 `到達性・公開範囲の変更` を除く）が 1 件以上あれば、`<SKILL_DIR>/references/must-verification.md` を Read し、その契約で `general-purpose` の反証サブエージェントを 1 体起動して Must 候補をまとめて渡す（`<REACHABILITY_CONTEXT>`・`<TARGET_FILES>`・base も渡す）。判定は次のとおり反映する。以降のカウント・サマリー表・詳細は反映後の重要度で出す。
   - 維持: そのまま。
   - 格下げ: 新しい重要度へ移し、`反証により格下げ（証拠: …）` を注記する。
   - 取り下げ: 指摘リストから外し、`## 🧪 反証で格下げ・取り下げた指摘` に証拠つきで列挙する。黙って消さない。

   Read 失敗・反証サブエージェントの失敗は止めず、Must を維持して `## 🧪 反証で格下げ・取り下げた指摘` の先頭行を `未実施（<理由>）` とする。候補単位で未実施のものは、その Must の詳細行の末尾に `（反証: 未実施・出力不完全）` と注記する。上記 fail closed の対象に含めないのは、反証は補助であり、欠けても網羅性は変わらないため。
6. `focus別カウント: A: N件, B: N件, …, I: N件, 到達性・公開範囲の変更: N件 (合計N件) → 重複統合M件 → 反証取り下げK件 → リストN-M-K件` を出力し、差分があれば原因を明記する。起動しなかった focus は件数の代わりに `未実行（対象ファイルなし）` と書く。以降の出力順は 🌐 到達性コンテキスト → 📊 サマリー → 重要度別の詳細 → 🧪 反証 → 🔍 確認できなかった範囲とする。
7. まず `## 🌐 到達性コンテキスト` として `<REACHABILITY_CONTEXT>` の review-reachability の表をそのまま出す（JSON ブロックは出さない。`未解決` のときはその旨と理由の 1 行）。続けて focus × 重要度のサマリー表を出力する。各セルは件数。起動しなかった focus の行と、到達性を解決しなかったときの `到達性・公開範囲の変更` の行は `未実行` とする。

```markdown
## 📊 Web セキュリティレビューサマリー

| focus | 🔴 Must | 🟡 Should | 🟢 Nice | 合計 |
|------|--------|-----------|---------|------|
| A インジェクション | 0 | 0 | 0 | 0 |
| … | | | | |
| I 配備・サプライチェーン | 未実行 | | | |
| 到達性・公開範囲の変更 | 0 | 0 | 0 | 0 |
| **合計** | 0 | 0 | 0 | 0 |
```

8. サマリー表に続けて、重要度別フォーマットで指摘の詳細を出力する。各指摘に `[ファイルパス:行番号]`・focus 名・Source→Sink を付け、Source→Sink の下に到達性の 1 行を足す（値は output-discipline.md の `到達性` と `既存の公開面`）。

```
## 🔴 Must（必ず修正）
- [path:line] (focus) 問題 → 修正案
  - Source→Sink: …
  - 到達性: … / 既存の公開面: …

## 🟡 Should（できれば修正）
- [path:line] (focus) 問題 → 修正案

## 🟢 Nice to have（提案）
- [path:line] (focus) 提案
```

9. 重要度別の詳細のあとに `## 🧪 反証で格下げ・取り下げた指摘` を出す。先頭行は固定文言の 3 状態のどれかにする: `対象なし（security の Must 候補 0 件）` / `実施: N 件を検証、格下げ X 件・取り下げ Y 件`（その下に格下げ・取り下げを証拠つきで列挙する） / `未実施（理由）`。最後に `## 🔍 確認できなかった範囲` を出し、ここを集約先とする: 各 focus・反証エージェント・到達性（review-reachability の末尾節。表だけを出し末尾節を捨てない）の「確認できなかった範囲」、失敗 focus の出力不完全、切り詰めの報告を重複を除いてまとめる。

全 focus で指摘がなかった場合は `Web セキュリティ観点では指摘はありません` と明記し、そのあとに「確認できなかった範囲」と未実行の focus を必ず併記する。失敗した focus・反証未実施・到達性未解決があればその旨も併記し、指摘なしを安全と読ませない。
