---
name: dotfiles-code-review
description: コード差分（Go / TypeScript・Vue・React / PHP・Laravel / IaC の Terraform・jsonnet / Dockerfile・CI・依存 lock）を、観点ごとの rubric を持つ専任サブエージェントに並列で分担させてレビューし、統合した重要度別の指摘リストを返す。言語は差分から判定し、言語が混在する差分も 1 回の実行で見る。コードは修正せず、PR への投稿もしない（PR への投稿・改修まで行うのは dotfiles-review-and-act）。「レビューして」「差分を見て」「Go / TS / PHP のレビューして」「フロントのレビューして」「Laravel の差分を見て」「IaC をレビュー」「Terraform の差分を見て」「module 構成を見て」「IAM 権限を見て」「DB / テスト / ログ / 設計の観点だけ見て」等で発動。観点を絞るときは --focus を使う。セキュリティだけなら review-web-security。
allowed-tools: [Bash, Read, Grep, Glob, Agent]
---

# /dotfiles-code-review

`<base>...HEAD` の差分を言語ファミリーごとに分け、観点の rubric（`## Focus ...` ブロック）1 つにつき 1 体のサブエージェントへ並列に分担させてレビューし、統合した指摘リストを出す。レビューのみ行い、ファイルは編集しない。

- メインセッションから起動する。サブエージェントに包まない（包むと、中継と統合だけを担う層が 1 段増える）。Agent が使えない場合（サブエージェントの中で呼ばれた等）は、1 体のインラインレビューで代替せずに停止し、`このスキルはメインセッションから起動してください。実装を担当するサブエージェントは lint/test までを行い、レビューは独立した検証としてメインから起動します` と返す。1 体に全 rubric を持たせて見落としが増えないかは未検証で、代替を許すとそのリスクを持ち込むため。
- セキュリティの rubric・出力規律・反証の契約の正本は `review-web-security`、到達性は `review-reachability`、別エージェントのセカンドオピニオンは `references/cross-review.md`。

## Input

- `--base=<branch>`: optional。解決は `skill-resolve-diff` に委譲する（`origin/master`、無ければ `origin/main`）。
- `--focus=<観点>[,<観点>...]`: optional。起動する観点を絞る。観点名は下表の OWNER（`architecture` / `idioms` / `storage` / `test` / `observability` / `grpc` / `state` / `performance` / `security` / `iac` / `supply-chain`）。指定したときはセカンドオピニオンと横断チェックを実行しない（観点を絞った依頼に全体レビューの指摘が混ざるため）。到達性は `security` か `iac` を含むときだけ解決する。
- `--no-cross-review`: optional。セカンドオピニオン（別エージェントの公式レビュー）を実行しない。
- `--repo-dir=<path>`: optional。レビュー対象の作業ツリー（PR の head を展開した worktree など）。以下の `<REPO_ROOT>` はその絶対パス。無ければ手順1の前にカレントディレクトリで `git rev-parse --show-toplevel` を実行し、その結果とする（サブディレクトリで起動しても基準をリポジトリのルートにそろえるため）。対象が作業ディレクトリの外にあるときは必ず指定する: Bash の cwd がコマンドごとに作業ディレクトリへ戻り、`cd` だけでは別のリポジトリをレビューしてしまうため。

## ファミリーと rubric

`<SKILL_DIR>` はこのスキルの絶対パス（`~/.claude/skills/dotfiles-code-review`）、`<SEC_DIR>` は `~/.claude/skills/review-web-security` とする。相対パスにしない: サブエージェントや `test -r` の cwd はレビュー対象のリポジトリなので、`references/...` のままでは存在していても読めず、fail closed が誤って発動する。

| ファミリー | pathspec | OWNER と rubric | security の Sink 表 | 担当名（prompt の `<REVIEWER>`） |
|---|---|---|---|---|
| go | `'*.go' '*.sql' '*.proto'` | architecture / idioms / storage / test / observability / grpc: `<SKILL_DIR>/references/rubrics/go/<OWNER>.md`、security: `<SEC_DIR>/references/focus-blocks.md` | `<SEC_DIR>/references/sinks-go.md` | Go バックエンドコードレビュー |
| ts | `'*.ts' '*.tsx' '*.js' '*.jsx' '*.vue'` | architecture / idioms / state / performance / test: `<SKILL_DIR>/references/rubrics/ts/<OWNER>.md`、security: 同上 | `<SEC_DIR>/references/sinks-ts.md` | TypeScript / Vue / React フロントエンドコードレビュー |
| php | `'*.php' '*.blade.php' 'database/migrations/*'` | architecture / idioms / storage / test / observability: `<SKILL_DIR>/references/rubrics/php/<OWNER>.md`、security: 同上 | `<SEC_DIR>/references/sinks-php.md` | PHP / Laravel コードレビュー |
| iac | `'*.tf' '*.tfvars' '*.hcl' '*.jsonnet' '*.libsonnet'` | iac: `<SKILL_DIR>/references/rubrics/iac/iac.md` | なし | IaC（Terraform / jsonnet）コードレビュー |
| supply-chain | `'*Dockerfile*' '*.dockerfile' '*compose*.yml' '*compose*.yaml' '.github/workflows/*' '*go.mod' '*go.sum' '*composer.json' '*composer.lock' '*package.json' '*package-lock.json' '*pnpm-lock.yaml' '*yarn.lock' '*.npmrc'` | supply-chain: `<SEC_DIR>/references/focus-blocks-supply-chain.md` | なし | （review-web-security の prompt を使う。下記） |

## 起動ゲート

次の focus は、差分の**全ファイル**が条件に当たるときだけ起動する。ファミリーの pathspec ではなく全ファイルで判定するのは、OpenAPI の定義が go の pathspec に入らないため。

| rubric | focus | 条件 |
|---|---|---|
| go/storage | `## Focus A: DB Schema Design` | スキーマ |
| php/storage | `## Focus A: Migration And Schema Design` | スキーマ |
| go/grpc | `## Focus A: Schema Design And Backward Compatibility` | API スキーマ |

スキーマ:

```bash
git -C <REPO_ROOT> diff --quiet <base>...HEAD -- ':(glob,icase)**/*.sql' ':(glob,icase)**/migration/**' ':(glob,icase)**/migrations/**'
```

API スキーマ:

```bash
git -C <REPO_ROOT> diff --quiet <base>...HEAD -- ':(glob,icase)**/*.proto' ':(glob,icase)**/*.pb.go' ':(glob,icase)**/*openapi*.yaml' ':(glob,icase)**/*openapi*.yml' ':(glob,icase)**/*openapi*.json' ':(glob,icase)**/*swagger*.yaml' ':(glob,icase)**/*swagger*.yml' ':(glob,icase)**/*swagger*.json' ':(glob,icase)**/openapi/**/*.yaml' ':(glob,icase)**/openapi/**/*.yml' ':(glob,icase)**/openapi/**/*.json' ':(glob,icase)**/swagger/**/*.yaml' ':(glob,icase)**/swagger/**/*.yml' ':(glob,icase)**/swagger/**/*.json'
```

終了コード 1（条件に当たる変更がある）なら起動し、0 なら起動せずその focus を `未実行（起動条件なし）` として扱う。起動するときは、同じ pathspec で `git -C <REPO_ROOT> diff --name-only <base>...HEAD -- <ゲートの pathspec>` を実行し、ファミリーの `<TARGET_FILES>` に無いファイル（OpenAPI の定義など）をその focus の担当の対象ファイルに足す（差分本文には入らないので、担当は Read で全文を読む）。それ以外（コマンドの失敗）なら起動する。`git diff --name-only | rg -q` のようなパイプにしない: 終了コードが rg のものになり、git の失敗が「条件なし」に化けて focus が黙って外れる。`go/grpc` の `## Focus B` はゲートしない: ステータスコードとエラー分類の指摘はハンドラやユースケースのコードに出て、仕様ファイルが変わらない差分でも起きるため。

## Workflow

1. 差分ファイルの置き場を作る。`mktemp -d "${TMPDIR:-/tmp}/code-review.XXXXXX"` を実行し、返った絶対パスを `<DIFF_DIR>` とする。
2. ファミリーごとにレビュー範囲を解決し、`<DIFF_DIR>` に書く。5 ファミリーぶんをそれぞれ別のコマンドで実行する（並列可）。`--base` が指定されていなければ `--base` を付けずに実行し、返った JSON の `base` を以降の `<base>` とする（起動ゲート・到達性・セカンドオピニオンのコマンドもこれを使う）:

```bash
cd <REPO_ROOT> && skill-resolve-diff [--base <base>] -- <ファミリーの pathspec> > <DIFF_DIR>/<ファミリー>.json
```

   続けて `jq -r .diff <DIFF_DIR>/<ファミリー>.json > <DIFF_DIR>/<ファミリー>.diff` で差分本文を別ファイルにし、自分は `jq` で `base`・`files`・`truncated`・`truncated_files` だけを読む。差分本文はサブエージェントに参照で渡すので、自分のコンテキストには入れない（横断チェックとファミリー外のレビューで必要な範囲だけ Read する）。
3. base ブランチが解決できなければ、`skill-resolve-diff` のエラーメッセージをそのまま伝えて終了。
4. `git -C <REPO_ROOT> diff --name-only <base>...HEAD` を実行し、差分の全ファイルを `<ALL_FILES>` とする。空なら `レビュー対象の変更がありません` と伝えて終了。`files` が空のファミリーは以降扱わず、統合の出力で `対象ファイルなし` として名前だけ挙げる。
5. ファミリーごとに `files` を `<TARGET_FILES>`、`<DIFF_DIR>/<ファミリー>.diff` を `<DIFF_FILE>` とする。`truncated` が true のときは `truncated_files` を `<TRUNCATED_FILES>` として保持し、そのファミリーのサブエージェント全員に渡したうえで、切り詰めが起きた事実と落ちたファイル一覧をユーザーに報告する。黙って落とさない: 切断位置は commit が増えるたびに動くため、同じ PR でも実行ごとにレビュー範囲が変わる。
6. 起動する OWNER を決める。対象ファミリーの OWNER すべて（go / ts / php は security を含む）から、`--focus` があればそれ以外を外す。続けて「起動ゲート」のコマンドを実行し、条件に当たらない focus を外す。`--focus` を指定して起動する focus が 0 件になったら `--focus <指定値> に該当する観点がこの差分にありません` と伝えて終了する（表に無い観点名はその旨も挙げる）。指摘なしの出力にしない: 「見ていない」を「問題なし」と読ませないため。
   起動ゲートを評価したあとで、`<ALL_FILES>` のうち、どのファミリーの `files` にも、起動した focus に起動ゲートで足したファイルにも入らないものを `<OTHER_FILES>` とする（ゲートの評価前に決めると、OpenAPI の定義のようにゲートで go/grpc の担当へ足すファイルが「ファミリー外」でも重ねてレビューされるため）。
7. 起動する OWNER の rubric が読めることを `test -r` で確かめ、`rg -n '^## Focus' <rubric>` で focus の見出しを列挙する（本文はサブエージェントが読む）。security か supply-chain を起動するなら `<SEC_DIR>/references/output-discipline.md` が、security を起動するファミリーがあればそのファミリーの Sink 表が、supply-chain を起動するなら `<SEC_DIR>/SKILL.md` が読めることも確かめる。**どれか一つでも読めなければ停止する（fail closed）**。読めなかったパスを挙げ、`./install.sh` を実行して skill を再配置するよう伝えて終了する。一部だけで続行しない: 「その観点で指摘が0件だった」と「その観点をそもそも実行していない」が出力上区別できず、同じ PR を再レビューしたときに前回の指摘が理由なく消えるため。
8. `--focus` も `--no-cross-review` も無ければ `<SKILL_DIR>/references/cross-review.md` を Read する。読めなくても停止せず、セカンドオピニオンを `未実施（cross-review.md が読めない）` として続行する。focus block の fail closed と扱いを分けるのは、相手エージェントの所見は補助であり、欠けても自分側の観点の網羅性は変わらないため。
9. 次の 2 つを 1 つのアシスタントメッセージで起動する（focus サブエージェントより先。相手のレビューと到達性の解決を待つ数分を、こちらのレビューと重ねるため）。
   - セカンドオピニオンを実行するなら、`cross-review.md` の「起動」に従い `skill-cross-review --from <claude|codex> --base <base> --repo-dir <REPO_ROOT>` を起動する。
   - go / ts / php / iac のいずれかに `files` があり、かつ `--focus` が無いか `security` / `iac` を含むなら、`general-purpose` サブエージェントを 1 体起動し、`~/.claude/skills/review-reachability/SKILL.md` を Read してその手順に従わせる（`--base <base>` と、対象の作業ツリーが `<REPO_ROOT>` であることを渡す）。返った出力を `<DIFF_DIR>/reachability.md` に書き、`<REACHABILITY_CONTEXT>` とする。`SKILL.md` が読めない・サブエージェントが失敗した場合も停止せず、`未解決（<理由>）` として続行する（全指摘が「到達性: 未確定」になる）。補助なので fail closed にしない。条件に当たらず起動しないときは `<REACHABILITY_CONTEXT>` を `未実行（<理由: 配備・サプライチェーンだけの差分 / --focus に security・iac を含まない>）` とする。
10. 手順7で列挙した focus の見出し（起動ゲートで外したものを除く）1 つが 1 サブエージェント分の担当範囲。security の focus は到達性コンテキストを渡すので、到達性の解決を待ってから起動する。**実際に数え、その数だけ** `general-purpose` サブエージェントを**1つのアシスタントメッセージ内で一斉に並列起動**する。逐次実行やインラインレビューで代替しない。件数はここに書かず必ず数えること（ハードコードすると focus 追加時にドリフトする）。
11. 全サブエージェントとセカンドオピニオンの完了を待つ。
12. `--focus` が無ければ、統合の前に下記「横断チェック」と「ファミリー外のファイル」を自分で 1 回ずつ実施し、所見をそれぞれ観点 `横断`・`ファミリー外` として持つ。

## Subagent Prompt Shape

go / ts / php / iac の各サブエージェントには、そのファミリーの共有コンテキストと 1 つの focus を渡す。`<REVIEWER>` はファミリーの担当名、`<OWNER>` は観点名、`<RUBRIC_FILE>` はその OWNER の rubric の絶対パス、`<FOCUS_HEADING>` は手順7で列挙した見出し。go の storage 担当には差分に含まれる `.sql` ファイルも、go の grpc 担当には `.proto` ファイルも対象である旨を伝える。

差分と focus block はプロンプトに埋め込まず、ファイルを参照させる。20 体ぶん埋め込むと 1 応答の出力上限を超え、本文を書き写すと rubric の原本とずれるため。

security 担当には、共有プロンプトの末尾に次の指示を足す: 「最初に `<SEC_DIR>/references/output-discipline.md` と `<そのファミリーの Sink 表>` を Read すること。出力は output-discipline.md の出力フォーマット（到達性・既存の公開面・CWE を含む）に従い、共有プロンプトの出力フォーマットと「該当なし」の書き方よりこちらを優先する。focus block の「誤検知の注意」に当たるものは報告しない。」あわせて同じ末尾に、`到達性コンテキスト:` の見出しに続けて `<DIFF_DIR>/reachability.md を Read すること`（到達性を解決しなかったときは `<REACHABILITY_CONTEXT>` の 1 行）を足し、次の 1 行を足す: 「これは差分の所有者側による防御目的のレビュー。攻撃手順・PoC は書かず、欠けている検証と修正の方向で書く（詳細は output-discipline.md）。」到達性コンテキストは security 担当にだけ渡す（到達性は security の重要度にだけ効き、他観点のプロンプトを太らせないため）。

```text
あなたは <REVIEWER>（観点: <OWNER>）の1名のレビュー担当です。レビューのみ行い、ファイルは編集しないでください。

リポジトリのルート（Read は絶対パスで行い、git は `git -C <REPO_ROOT>` で実行する）:
<REPO_ROOT>

対象ファイル:
<TARGET_FILES>

ベースブランチ: <base>

差分:
<DIFF_FILE> を Read すること。

差分本文から切り詰めで落ちたファイル（空なら「なし」）:
<TRUNCATED_FILES>
※ ここに挙がったファイルは差分本文に含まれていない。必ず Read で全文を読むこと。差分に無いことを見落としの理由にしない。ただし削除されたファイルは Read できないため、その場合のみ対象外として扱う。

担当する focus:
<RUBRIC_FILE> を Read し、見出しが「<FOCUS_HEADING>」の節（その見出しから次の `## Focus` 見出しの直前まで）だけを担当範囲とする。

手順:
1. 差分を読み、変更されたファイルを Read ツールで全文読み取る。
2. Read ツールの実ファイル行番号で指摘する。diff の @@ 行番号は使わない。
3. 渡された focus の観点に厳密に絞る。他観点には触れない。
4. 命名・型・テストの配置は、明文化された規約と同じ責務を持つ既存ファイルの慣例を確認する。既存と違うだけでは不備とせず、好みだけの差を Must にしない。

出力フォーマット:
### [ファイルパス:行番号]
- **観点**: 担当した focus の見出し（`## Focus X: ...`）を逐語でそのまま書く。言い換え・要約・独自の観点名の創作はしない。
- **問題点**: (具体的に何が問題か)
- **Why**: (なぜ修正すべきか)
- **推奨する修正**: (どう修正すべきか)

該当する指摘がない場合は「該当なし」とだけ明記してください。
推測的・スタイルだけの指摘は避け、根拠を示せる具体的な指摘のみ報告してください。
```

supply-chain の focus は、`<SEC_DIR>/SKILL.md` の「Subagent Prompt Shape」を使う。`<SKILL_DIR>` には `<SEC_DIR>`、`<SINK_FILES>` には「なし」、到達性コンテキストには `未解決（配備・サプライチェーンでは使わない）` を入れ、対象ファイルは supply-chain ファミリーのものを渡す。リポジトリのルート・差分・focus block は、上の形と同じく参照で渡す。

## ファミリー外のファイル（自分でレビュー）

`<OTHER_FILES>`（どのファミリーの pathspec にも当たらない変更ファイル）は、自分で Read して、グローバル指示の基本観点（レイヤー境界 / エラー処理 / 命名・可読性 / テスト / セキュリティ / パフォーマンス）でレビューする。アクセス制御の規則（Firestore rules 等）・設定ファイル・スクリプトのように、言語の rubric が無くても挙動やセキュリティに効くファイルを、ほかのファミリーがある差分で取りこぼさないため。削除されたファイルは Read できないので、`git -C <REPO_ROOT> diff <base>...HEAD -- <path>` で消えた内容を読む。バイナリ（`git -C <REPO_ROOT> diff --numstat <base>...HEAD` で行数が `-` になるもの）は内容を見ず、名前だけ 📁 に挙げる。

## 横断チェック（自分で全ファミリーの差分に対して実施）

各 focus サブエージェントは単一観点に閉じるため、**差分全体を俯瞰しないと判断できない次の観点は自分で確認する**。サブエージェントには渡さない（観点をまたいだ重複指摘を避けるため）。所見は観点名 `横断` として統合結果に含める。横断チェックは自分が 1 回実施する網羅チェックリストであり、サブエージェントに分散されないため focus の「1 focus 8観点以下」ルールは適用しない（項目が増えたら分割ではなく自分の負荷で要否を判断する）。

- **責務と情報の正本**: 必須の判定を誰が担い、必要な情報をどこから・いつ取得するかを追う。呼び出し元の準備不足や省略可能な引数で、仕様上必須の検証を迂回できないか、実際の呼び出し経路で確認する。特定レイヤーへの集約を一律に求めず、既存の責務境界と必要な整合性から判断する。
- **共有契約と利用側**: 型・エラー・状態などの共有契約へ追加するときは、生成・変換・分岐・表示まで利用側を追う。個別の別扱いが、必要な契約の違いによるものか、実装都合だけの例外かを確認する。別の契約が必要なものまで統合しない。
- **表現の境界での意味**: 同じ概念が言語・API・保存形式などをまたぐ場合、値だけでなく型・欠損・正規化・比較規則の意味を照合する。関係する入力と実際の変換・比較処理を確認し、型注釈や自作の fake 同士の一致だけで等価としない。意味が分かれる境界は、期待する振る舞いをテストで確認する。
- **整合性 / parity**: 機構と責務が同じ既存実装を比較し、仕様上そろえるべき振る舞いが一致するか確認する。意図した差や既存の不具合まで機械的にそろえない。同じ原因の見落としが疑われる場合は、共有契約・呼び出し先・同じ比較処理を起点に類似箇所を探す。確認した範囲と未確認の範囲を示し、差分外の既存問題は今回の変更による問題と分けて報告する。
- **diff スコープ / PR 衛生**: 1 PR・1 commit が単一の意味単位に収まっているか。無関係な変更・ついでの修正が混入していないか。純粋なリファクタ/フォーマットとロジック変更が同じ commit に混ざっていないか。混在していれば指摘し、分割を促す。
- **ドキュメントと実装の整合**: リポジトリ内の README・アーキ図・使用例・doc コメントが実装と食い違っていないか。使用例に必須変数が抜けてコピペで失敗する、新規モジュール/機能がトップレベルの構成説明に載っていない、保持世代数など README の記述が実挙動と逆、等。PR 本文・Jira との齟齬は別枠（review-and-act の仕様適合）で見るため、ここではリポジトリ内ドキュメントに絞る。
- **デプロイ前提・データ非互換の明示**: マージしただけでは動かない前提（クライアント登録・契約企業ごとの有効化・リダイレクト URI 追加等）や、既存の発行済み資産が無効になる変更（cookie の開封不能化等）が、PR 説明やマイグレーション手順に明記されているか。未記載なら事故になるため指摘する。
- **マージ順序・中間状態の露出**: 依存する別 PR とのマージ順で、単独マージすると骨格だけ・固定値のまま等の中間状態が本番に露出しないか。インフラだけ先に apply される等の意図が PR 本文に書かれているか。
- **配線の完結性**: 権限やリソースは作られたが、その値がアプリに届いていない状態になっていないか（キューは作られ送信権限も付いたが、URL がアプリの環境変数にも outputs にも渡っておらず送信処理を実装できない等）。片側だけ用意して繋がっていない配線を指摘する。
- **上限値と下位層制約の整合**: アプリ層で設けた上限・件数が、下位層やプラットフォームの制約と整合しているか（条件数の上限より先に CDN の URL 長制限に当たり実効的に機能しない等）。上限が名目だけになっていないか確認する。

## Integration

観点名は go / ts / php では `<ファミリー>/<OWNER>`（例 `go/storage`・`ts/security`）、iac は `iac`、supply-chain は `supply-chain` とする。security と supply-chain をまとめて「security 系」と呼ぶ。

全サブエージェントが返ったら:

1. 観点ごとに指摘件数をカウントする。横断チェックとファミリー外のレビューの所見は、観点 `横断`・`ファミリー外` として含める（`--focus` 時と、`<OTHER_FILES>` が無いときの `ファミリー外` は `未実行`）。セカンドオピニオンは先に `cross-review.md` の「結果の扱い」で検証・分類し、検証済みで自分側と重複しないものを観点 `second opinion` として含める。到達性コンテキストに exposure findings があれば観点 `到達性・公開範囲の変更` として含める。実行しなかった観点は 0 件と数えず、カウント行・サマリー表・📁 では `未実行` と書く（`--focus` 時の `横断` と `second opinion`、`--no-cross-review` 時・`cross-review.md` が読めないとき・`skill-cross-review` が `skipped` / `failed` を返したときの `second opinion`、解決しなかった到達性）。🔁 節と 🧪 節では、それぞれの文書の定めどおり `未実施（理由）` と書く。
   起動ゲートで外した focus は、その観点の件数に `（未実行: Focus X 起動条件なし）` を併記する。security 系の担当の出力に `確認できなかった範囲` 節が無い、またはエラー・拒否文で終わっている場合、その focus を 0 件として数えず「失敗」とし、成功した focus 分の件数に `（失敗: focus X）` を併記して、`確認できなかった範囲` に `focus X: 出力不完全（再実行を推奨）` を載せる。「該当なし」でも節があれば正常として扱う: 「0 件」と「実行できていない」を出力上区別するため。
2. 各指摘がその担当に渡した対象ファイル（ファミリーの `<TARGET_FILES>` と、起動ゲートで足したファイル。`ファミリー外` は `<OTHER_FILES>`）を参照しているか検証し、対象外は警告付きで分離する。あわせて各指摘の行番号を、`<REPO_ROOT>` の実ファイルを Read して確かめ、指摘内容と合わない行なら正しい行に引き直す（サブエージェントは行番号を取り違えることがあり、ずれた行は PR へのインライン投稿で拒否される）。
3. 統合は「同一ファイル・同一行・同一の focus 見出し（逐語一致）」の場合のみ行い、統合時は元の観点名を併記する。サブエージェントが見出しを言い換えていた場合は、言い換えのまま統合せず focus block の見出しに引き直す。ただし観点 `到達性・公開範囲の変更` は focus block ではないので引き直さない。
4. 重複統合の後・反証の前に、security 系の指摘の重要度を確定する。`重要度案` を採用し、根拠が `output-discipline.md` の軸に沿っていない場合だけ調整して、調整した旨と理由を指摘に注記する。iac の指摘は、権限過剰・本番影響・apply が壊れる（count / for_each の apply 時依存、破壊的な lifecycle）を Must、命名・module 境界・未使用宣言など保守性を Should、表現の一貫性・将来の改善余地を Nice とする。
5. 調整後の security 系の Must 候補（観点 `到達性・公開範囲の変更` を除く）が 1 件以上あれば、`<SEC_DIR>/references/must-verification.md` を Read し、その契約で `general-purpose` の反証サブエージェントを 1 体起動して Must 候補をまとめて渡す（`<REACHABILITY_CONTEXT>`・対象ファイル・base も渡す）。判定は次のとおり反映し、以降のカウント・サマリー表・詳細は反映後の重要度で出す。
   - 維持: そのまま。
   - 格下げ: 新しい重要度へ移し、`反証により格下げ（証拠: …）` を注記する。
   - 取り下げ: 指摘リストから外し、`## 🧪 反証で格下げ・取り下げた指摘` に証拠つきで列挙する。黙って消さない。

   Read 失敗・反証サブエージェントの失敗は止めず、Must を維持して `## 🧪 反証で格下げ・取り下げた指摘` の先頭行を `未実施（<理由>）` とする。候補単位で未実施のものは、その Must の詳細行の末尾に `（反証: 未実施・出力不完全）` と注記する。補助なので fail closed にしない。
6. `観点別カウント: <観点>: N件, …, 横断: N件, ファミリー外: N件, 到達性・公開範囲の変更: N件, second opinion: N件 (合計N件) → 重複統合M件 → 反証取り下げK件 → リストN-M-K件` を出力し、差分があれば原因を明記する。`未実行` の観点は件数の代わりに `未実行` と書き、続けて `対象ファイルなし: <ファミリー名の列挙>` を 1 行出す（無ければ `なし`）。以降の出力順は 🌐 到達性コンテキスト → 📊 サマリー → 重要度別の詳細 → 🧪 反証 → 🔁 セカンドオピニオン → 🔍 確認できなかった範囲（security 系） → 📁 レビュー範囲とする。
7. `## 🌐 到達性コンテキスト` として `<REACHABILITY_CONTEXT>` の review-reachability の表をそのまま出す（JSON ブロックは出さない。`未解決` / `未実行` のときはその旨と理由の 1 行）。続けて観点 × 重要度のサマリー表を出す。行は起動した観点と `横断` / `ファミリー外` / `到達性・公開範囲の変更` / `second opinion` / 合計。各セルは件数で、指摘がなければ `0`、実行しなかった行は `未実行` とする。

```markdown
## 📊 レビューサマリー

| 観点 | 🔴 Must | 🟡 Should | 🟢 Nice | 合計 |
|------|--------|-----------|---------|------|
| go/architecture | 0 | 0 | 0 | 0 |
| … | | | | |
| 横断 | 0 | 0 | 0 | 0 |
| ファミリー外 | 0 | 0 | 0 | 0 |
| 到達性・公開範囲の変更 | 0 | 0 | 0 | 0 |
| second opinion | 0 | 0 | 0 | 0 |
| **合計** | 0 | 0 | 0 | 0 |
```

8. サマリー表に続けて、重要度別フォーマットで指摘の詳細を出す。各指摘に `[ファイルパス:行番号]` と観点名を付ける。security 系の指摘には Source→Sink を併記し、その下に `  - 到達性: … / 既存の公開面: …` の 1 行を足す（値は output-discipline.md の `到達性` と `既存の公開面`）。

```
## 🔴 Must（必ず修正）
- [path:line] (観点) 問題 → 修正案

## 🟡 Should（できれば修正）
- [path:line] (観点) 問題 → 修正案

## 🟢 Nice to have（提案）
- [path:line] (観点) 提案
```

9. 重要度別の詳細のあと（`確認できなかった範囲` より前）に、まず `## 🧪 反証で格下げ・取り下げた指摘` を出す。先頭行は固定文言の 3 状態のどれかにする: `対象なし（security の Must 候補 0 件）` / `実施: N 件を検証、格下げ X 件・取り下げ Y 件`（その下に格下げ・取り下げを証拠つきで列挙する） / `未実施（理由）`。続けて `cross-review.md` の「出力」に従って `## 🔁 セカンドオピニオン（<reviewer>）` 枠を出す。実行しなかった・失敗した場合も `未実施（理由）` の 1 行を出す。最後に `## 🔍 確認できなかった範囲（security 系）` を出し、ここを集約先とする: security 系の各 focus・反証エージェント・到達性（review-reachability の末尾節。表だけを出し末尾節を捨てない）の「確認できなかった範囲」、失敗 focus の出力不完全、切り詰めの報告を重複を除いてまとめる。
10. 最後に `## 📁 レビュー範囲` として、ファミリーごとに `<TARGET_FILES>`（サブエージェントに渡したファイル。起動ゲートで足したファイルも含む）と `<TRUNCATED_FILES>`（差分本文から落ちたファイル）を列挙し、focus 見出しごとに `実行` / `未実行（理由）` / `失敗` を 1 行で書く。`ファミリー外` は `<OTHER_FILES>` を列挙して `実行` / `未実行（理由）` を書き、`横断`・`到達性・公開範囲の変更`・`second opinion` も 1 行ずつ書く。呼び出し元（`dotfiles-review-and-act`）が前回指摘の解決確認で「今回どのファイルをどの focus で見たか」を判定する根拠にする。

全観点で指摘がなかった場合は `全観点でレビューの指摘はありません` と明記し、起動ゲートで外した focus・失敗した focus・反証未実施・到達性未解決・確認できなかった範囲があればその旨を併記し、指摘なしを安全と読ませない。
