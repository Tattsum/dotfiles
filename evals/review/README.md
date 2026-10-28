# レビュースキルの評価ケース

`dotfiles-code-review`（と、その security 観点の正本である `review-web-security`）が、意図した指摘を出し、誤検知をしないかを測る。インストール済みのスキルを `claude -p` でそのまま動かし、出力を決定的に採点する。

## 回し方

`claude` を起動するので、利用枠を消費する（Team / Enterprise のログインならシートの利用枠。サブエージェントの分も同じ枠から引かれる。API キーなら従量課金）。Claude Code の sandbox の中から起動すると sandbox が入れ子になって動かないので、ターミナル（または Claude Code の `!`）から実行する。

```bash
# 1 ケースの片側を 1 回だけ（まず 1 回の費用を測る）
evals/review/run.sh --max-budget-usd 5 --case unique-check-scope/defect

# 全ケースを 3 回ずつ
evals/review/run.sh --max-budget-usd 10 --runs 3
```

`--max-budget-usd` は `claude` の 1 回の実行ごとの上限で、既定値は無い。判定に使うのは定価換算の見積もり（`total_cost_usd`）で、実際の請求やプランの利用枠の残りは見ない。見積もりは回の規模を比べる目安として `score.json` に残し、最後に集計を表示する。

2026-10-28 の実測（下の固定の設定、定価換算の見積もり）では、security のケースが 1 回 3.5〜4.5 ドル・30〜140 秒、test と storage のケースが 1 回 1.0〜1.4 ドル・20〜100 秒だった。security は観点のサブエージェントが 8 体動くので桁が違う。全ケースを 3 回ずつ回すと、約 60 ドル・約 22 分になる。上限が実際の規模を下回ると途中で打ち切られて不合格になるので、最大の実測値の 2 倍程度にしておく。

評価では次の設定に固定し、使った設定を `meta.json` に残す。ふだんの設定（ultracode や advisor）のままだと、回ごとに挙動と費用がぶれるため。

| 項目 | 値 | 上書き |
|---|---|---|
| モデル | `claude-opus-5-5` | `REVIEW_EVALS_MODEL` |
| effort | `xhigh`（`CLAUDE_CODE_EFFORT_LEVEL` は外す） | `REVIEW_EVALS_EFFORT` |
| 権限のモード | `auto` | `REVIEW_EVALS_PERMISSION_MODE` |
| ultracode | 無効（`--settings '{"ultracode": false}'`） | なし |
| advisor | 無効（`CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1`） | なし |
| 自動のメモリ | 無効（`CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`）。回どうしで覚えた内容を引き継がない | なし |
| 会話とプロンプトの履歴 | 残さない（`--no-session-persistence`、`CLAUDE_CODE_SKIP_PROMPT_HISTORY=1`） | なし |
| 親のセッションの環境変数 | 外す（一覧は `bin/skill-cross-review` と同じ）。`!` から起動しても入れ子にならない | なし |

## ケースの形

`cases/<名前>/` に 1 つの観点の対を置く。

- `case.json`: 回す観点（`focus`）、照合する観点名（`perspective`）、見つけるべき指摘（`defect.expect`）、誤検知を見るファイル（`clean.paths`）
- `base/`: 両方に共通の元のコード
- `defect/`: base に重ねる、指摘すべき欠陥を含むファイル
- `clean/`: base に重ねる、同じ仕組みで欠陥を含まないファイル

fixture は `$TMPDIR/review-evals/<ハッシュ>` に作り直し、`main`（base）と `feature`（head）の 2 コミットにする。パス・ブランチ名・コミットメッセージに、ケース名や defect / clean を出さない（レビュー担当から見え、答えになる）。このリポジトリの中で回さないのも同じ理由で、このリポジトリのメモリ（足した観点）が読み込まれてしまうため。ハッシュとケースの対応は `meta.json` の `fixture` に残る。

ケースは手書きの最小の再現で作り、実在のリポジトリのコードは使わない。fixture のパスに角括弧を入れない（指摘の `[path:line]` と区別できなくなる）。`.sql` も置かない（置くと Go ファミリーの全担当が起動する）。

## 採点

`score.go` が、`claude -p --output-format json` の出力を `case.json` と照合する。

- 共通: 観点別カウントの行で、対象の観点が件数付きで実行されている（失敗・未実行の注記が無い）。`--focus` では横断とセカンドオピニオンが正当に未実行になるので、対象の観点だけを見る。
- 共通: 観点別カウントの行の「リストN件」と、読み取れた指摘の数が一致する。一致しないのは指摘の書式がずれたときなので、「採点できない」として不合格にする。そのまま採点すると、clean で誤検知を見落として合格にしてしまう。指摘の行は、見出しを太字で包んだ `- **[path:line] …**` も読む。
- defect: 期待する指摘ごとに、path が一致し、行が範囲の前後 3 行以内で、観点名が一致し、重要度が下限以上で、本文にキーワードのどれかを含む指摘がある。
- clean: `clean.paths` のファイルへの指摘が 0 件。

LLM による判定は使っていない。`claude.json` に生の出力が残るので、採点の規則を変えたらレビューを回し直さずに採り直せる。

```bash
cd evals/review && go run score.go -case cases/<名前>/case.json -variant defect -output results/<時刻>/<名前>/defect/run-1/claude.json
cd evals/review && go run score.go summary results/<時刻>
```

`score.go` は標準ライブラリだけで書いてあり、go.mod 無しで動く。テストは `cd evals/review && go test score.go score_test.go`、`run.sh` の配線のテストは `tests/review-evals-run-test.sh`（偽の `claude` を使うので課金は無い）。

## 結果と後片付け

結果は `evals/review/results/<時刻>/<名前>/<defect|clean>/run-<n>/` に、`meta.json`・`claude.json`・`claude.stderr`・`claude.exit`・`score.json` を置く（`.gitignore` 済み）。集計は `<時刻>/summary.json`。

fixture は `$TMPDIR/review-evals/` に残るので、不要になったら消す。
