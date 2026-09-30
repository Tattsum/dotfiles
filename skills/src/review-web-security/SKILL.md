---
name: review-web-security
description: Web アプリの差分を、書籍『Webアプリケーションセキュリティ入門』（yousukezan）準拠の言語横断セキュリティ観点でレビューするとき。コード用の 8 focus（インジェクション / XSS・クライアントサイド / 認証・セッション・CSRF / 認可・API 契約 / 状態・業務ロジック / SSRF・外部 I/O / ファイル / 情報露出・ログ・本番設定）と、Dockerfile・CI workflow・依存 lock が差分にあるときだけ動く配備・サプライチェーン focus を専任サブエージェントで並列実行し、Go / PHP-Laravel / TS の言語別 Sink 表を引きながら Source→Sink 付きの Must / Should / Nice で報告する。コードは修正しない。「セキュリティレビューして」「Web セキュリティを見て」「認可漏れ・SQLi・XSS・SSRF をチェック」「Dockerfile や CI のセキュリティを見て」等で発動。言語別オーケストレーター（dotfiles-go-review / dotfiles-php-laravel-review / dotfiles-ts-review）もセキュリティ観点としてこの focus を読み込む。
allowed-tools: [Bash, Read, Grep, Glob, Agent]
---

# /review-web-security

Web アプリの `<base>...HEAD` 差分を、言語に依存しないセキュリティ観点の focus ごとに専任サブエージェントへ分担させてレビューし、統合した指摘リストを出す。レビューのみ行い、ファイルは編集しない。

- 観点の正本は `references/focus-blocks.md`（コード用 A〜H）と `references/focus-blocks-supply-chain.md`（配備・サプライチェーン I）。言語別の危険 API は `references/sinks-go.md` / `sinks-php.md` / `sinks-ts.md`、出力の規律と重要度の軸は `references/output-discipline.md`。
- Claude Code 組み込みの `/security-review` は、確度の高い脆弱性を単発で洗い出す汎用スキャン。本スキルは言語別 Sink 表・書籍準拠の誤検知の注意・Must / Should / Nice を持ち、言語別オーケストレーターからも読み込まれる常設のレビュー観点という位置づけ。
- Agent（サブエージェント）が使えない環境では、このスキルはユーザーセッションから直接起動する必要がある（インラインの単発レビューでは代替しない）。

## Input

- `--base=<branch>`: optional。解決は `skill-resolve-diff` に委譲する（`origin/master`、無ければ `origin/main`）。
- `--scope=all|code|supply-chain`: optional。既定は `all`。`dotfiles-review-and-act` は言語別オーケストレーターがコード用 focus を担うため `--scope=supply-chain` で呼ぶ。

## Scope

対象:
- コード（A〜H）: インジェクション、XSS とクライアントサイド、認証・セッション・CSRF、認可と API 契約、状態と業務ロジック、SSRF と外部 I/O、ファイル、情報露出・ログ・本番設定
- 配備とサプライチェーン（I）: Dockerfile、compose、`.github/workflows/*`、依存の manifest と lock、レジストリ設定

対象外:
- コードの修正
- Terraform / OpenTofu / jsonnet の IaC: `review-iac`
- 新規依存を採用するかどうかの判断: `dotfiles-plan-first` の Phase 2
- ログの一般的な品質（コンテキスト・ログレベル）: `review-go-observability` / `review-php-observability`
- AI エージェント Skill 自体のセキュリティ: `review-skill-security`
- レイヤー責務・命名・型安全・DB スキーマ・テスト戦略: 各言語の専用スキル

## Workflow

`<SKILL_DIR>` はこのスキルのディレクトリの絶対パス（`~/.claude/skills/review-web-security`）とする。以下の参照ファイルはすべて `<SKILL_DIR>` 起点で扱う。相対パスにしないこと: サブエージェントや `test -r` の cwd はレビュー対象のリポジトリなので、`references/...` のままでは存在していても読めず、fail closed が誤って発動する。

1. `--scope` が `all` か `code` なら、コードの範囲を解決する:

```bash
skill-resolve-diff --base <base> -- '*.go' '*.php' '*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs' '*.cjs' '*.vue' '*.sql' '*.html' '*.tmpl' '*.gohtml'
```

2. `--scope` が `all` か `supply-chain` なら、配備・サプライチェーンの範囲を解決する:

```bash
skill-resolve-diff --base <base> -- '*Dockerfile*' '*.dockerfile' '*compose*.yml' '*compose*.yaml' '.github/workflows/*' '*go.mod' '*go.sum' '*composer.json' '*composer.lock' '*package.json' '*package-lock.json' '*pnpm-lock.yaml' '*yarn.lock' '*.npmrc'
```

3. base ブランチが解決できなければ `ブランチ <base> が見つかりません` と伝えて終了。
4. 解決した範囲のファイルがすべて空なら終了する。`--scope=supply-chain` なら `配備・サプライチェーンの対象ファイルはありません（focus I は未実行）`、それ以外は `レビュー対象のファイルがありません` と伝える。
5. 範囲ごとに `files` を `<TARGET_FILES>`、`diff` を `<DIFF_CONTEXT>` として保持する。`truncated` が true のときは `truncated_files` を `<TRUNCATED_FILES>` として保持し、その範囲のサブエージェント全員に渡したうえで、切り詰めが起きた事実と落ちたファイル一覧をユーザーに報告する。黙って落とさない: 切断位置は commit が増えるたびに動くため、同じ PR でも実行ごとにレビュー範囲が変わる。
6. コードの範囲の `languages`（go / php / ts）に対応する `<SKILL_DIR>/references/sinks-<lang>.md` を `<SINK_FILES>` とする。該当が無ければ `<SINK_FILES>` は「なし（言語非依存の観点だけで確認する）」とする。
7. 使う focus 定義を Read する。コードのファイルがあれば `<SKILL_DIR>/references/focus-blocks.md`、配備・サプライチェーンのファイルがあれば `<SKILL_DIR>/references/focus-blocks-supply-chain.md`。あわせて `<SKILL_DIR>/references/output-discipline.md` と `<SINK_FILES>` が読めることを `test -r` で確認する（本文はサブエージェントが読む）。**どれか一つでも読めなければ停止する（fail closed）**。読めなかったパスを挙げ、`./install.sh` を実行して skill を再配置するよう伝えて終了する。一部だけで続行しない: 「その focus で指摘が0件だった」と「その focus をそもそも実行していない」が出力上区別できず、同じ PR を再レビューしたときに前回の指摘が理由なく消えるため。
8. 読み込んだファイル内の `## Focus ...` ブロックが1サブエージェント分の担当範囲。**読み込めた focus block を実際に数え、その数だけ** `general-purpose` サブエージェントを**1つのアシスタントメッセージ内で一斉に並列起動**する。コード用の focus にはコードの範囲、focus I には配備・サプライチェーンの範囲を渡す。逐次実行やインラインレビューで代替しない。件数はここに書かず必ず数えること（ハードコードすると focus 追加時にドリフトする）。
9. 全サブエージェントの完了を待つ。

## Subagent Prompt Shape

各サブエージェントには、下記の共有コンテキストと 1 つの focus block を渡す。`<SKILL_DIR>` と `<SINK_FILES>` は Workflow で決めた絶対パスをそのまま入れる。focus I には `<SINK_FILES>` として「なし」を渡す。

```text
あなたは /review-web-security の1名のレビュー担当です。レビューのみ行い、ファイルは編集しないでください。

最初に次を Read すること:
- <SKILL_DIR>/references/output-discipline.md（読み方・出力フォーマット・重要度案の付け方）
- 言語別 Sink 表: <SINK_FILES>

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
1. 差分を読み、変更されたファイルを Read ツールで全文読み取る。Source や Sink が差分の外にあるときは、呼び出し元・呼び出し先も Read してたどる。
2. Read ツールの実ファイル行番号で指摘する。diff の @@ 行番号は使わない。
3. 渡された focus の観点に厳密に絞る。他の focus には触れない。
4. focus block の「誤検知の注意」に当たるものは報告しない。

出力は output-discipline.md の「出力フォーマット」に従う（観点 / 問題点 / Source→Sink / Why / 推奨する修正 / 重要度案、最後に「確認できなかった範囲」）。
該当する指摘がない場合は、先頭行を「該当なし」とし、そのあとに「確認できなかった範囲」の節を付けること。
```

## Integration

全サブエージェントが返ったら:

1. focus ごとに指摘件数をカウントする。
2. 各指摘が `<TARGET_FILES>` 内のファイルを参照しているか検証し、対象外は警告付きで分離する。
3. 統合は「同一ファイル・同一行・同一の focus 見出し（逐語一致）」の場合のみ行う。サブエージェントが見出しを言い換えていた場合は、言い換えのまま統合せず focus block の見出しに引き直す。
4. 重要度はサブエージェントの `重要度案` を採用する。根拠が `output-discipline.md` の軸に沿っていない場合だけ調整し、調整した旨と理由を指摘に注記する。
5. `focus別カウント: A: N件, B: N件, …, I: N件 (合計N件) → 重複統合M件 → リストN-M件` を出力し、差分があれば原因を明記する。起動しなかった focus は件数の代わりに `未実行（対象ファイルなし）` と書く。
6. focus × 重要度のサマリー表を出力する。各セルは件数。起動しなかった focus の行は `未実行` とする。

```markdown
## 📊 Web セキュリティレビューサマリー

| focus | 🔴 Must | 🟡 Should | 🟢 Nice | 合計 |
|------|--------|-----------|---------|------|
| A インジェクション | 0 | 0 | 0 | 0 |
| … | | | | |
| I 配備・サプライチェーン | 未実行 | | | |
| **合計** | 0 | 0 | 0 | 0 |
```

7. サマリー表に続けて、重要度別フォーマットで指摘の詳細を出力する。各指摘に `[ファイルパス:行番号]`・focus 名・Source→Sink を付ける。

```
## 🔴 Must（必ず修正）
- [path:line] (focus) 問題 → 修正案
  - Source→Sink: …

## 🟡 Should（できれば修正）
- [path:line] (focus) 問題 → 修正案

## 🟢 Nice to have（提案）
- [path:line] (focus) 提案
```

8. 最後に、各サブエージェントの「確認できなかった範囲」を重複を除いてまとめ、`## 🔍 確認できなかった範囲` として出力する。

全 focus で指摘がなかった場合は `Web セキュリティ観点では指摘はありません` と明記し、そのあとに「確認できなかった範囲」と未実行の focus を必ず併記する（指摘なしを「安全」と読ませないため）。
