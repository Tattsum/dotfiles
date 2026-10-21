---
name: dotfiles-pr-create
description: push 済みのブランチから GitHub の Pull Request を作成するとき。base の自動判定、PR テンプレート優先・無ければコミット規約ミラーの本文生成、既定 draft での作成を担う。commit / push は dotfiles-commit-push の責務として扱い、ここでは行わない。
---

## 目的

push 済みのブランチから `gh pr create` で PR を作成する**専任**スキル。
ブランチ作成・コミット・push は `dotfiles-commit-push` の責務であり、このスキルでは行わない。

## 前提コマンド

- `gh`（GitHub CLI、認証済み）
- `git`

## プリフライト（いずれかに該当したら PR を作らず中断して案内する）

PR 作成の前に必ず以下を確認し、満たさない場合は**作成せず**理由を伝えて終了する。

- 現在のブランチがデフォルトブランチ（main / master 等）→ 「PR 用のブランチに切り替えてください」と案内
- upstream（追跡ブランチ）が未設定、または未 push のコミットがある → 「先に `dotfiles-commit-push` で commit / push してください」と案内
- ローカルがリモートより先行している（未同期）→ 同上で push を促す

確認コマンド例:

```bash
git rev-parse --abbrev-ref HEAD                 # 現在ブランチ
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null # upstream（無ければ未設定）
git status -sb                                  # ahead/behind の確認
```

デフォルトブランチは git と同じ呼び出しにまとめず、**単独の Bash 呼び出し**で取得する（まとめると sandbox の `gh *` 除外が効かず sandbox 内で動いて失敗する）。

```bash
gh repo view --json defaultBranchRef -q .defaultBranchRef.name
```

## base ブランチ

- 既定: `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` で取得したデフォルトブランチ
- 引数で base が明示された場合はそれを優先（リリースブランチ・stacked PR 等）
- stacked PR（base を別の PR のブランチにしたもの）は、依存が本質的でなければ独立した PR に分けるよう提案する（利用者が明示した base は変えない）。重ねるなら、下位をマージし、上位の base が main に張り替わったのを確かめてから上位をマージする。張り替わる前に上位をマージすると、上位の内容は下位のブランチに入るだけで main に届かないのに、GitHub は両方を MERGED と表示する
- マージの後は、fetch してから各 PR の main への到達を確かめる（`gh pr view <n> --json mergeCommit -q .mergeCommit.oid` で取ったコミットに `git merge-base --is-ancestor <oid> origin/main`）。`mergeCommit` が空なら未マージ。祖先でなくても、squash マージで祖先関係が切れているだけのことがあるので、`git diff origin/main <上位のブランチ>` に上位の変更が残っているかを見る。残っていれば、上位のブランチから main 向けの PR を作り直す

## タイトル

- **Emoji は付けない。**
- コミットが 1 つだけ: そのコミットのタイトルから先頭 Emoji を除去した要約を流用する
- コミットが複数: 差分とコミットログから簡潔な要約を生成する

## 本文

優先順位で決定する。

1. リポジトリに `.github/PULL_REQUEST_TEMPLATE.md`（または `docs/`・`.github/PULL_REQUEST_TEMPLATE/` 配下）が存在する → **そのテンプレートを最優先**で埋める
2. テンプレートが無い → 下記のコミット規約ミラー構成を**日本語**で生成する

```markdown
## 概要
<変更の要点を箇条書き>

## Reason（なぜ）
<git log の各コミットの Reason を集約>

## Specification（仕様・意図）
<git log の各コミットの Specification を集約。設計判断・トレードオフを残す>

## 動作確認
- [ ] <人が記入する未チェックのチェックリスト>
```

- 本文は `git log <base>..HEAD` の Reason / Specification を集約して質を安定させる。テンプレートに理由の欄が無くても、テンプレートの構成は崩さずに、概要の欄などへ Reason（なぜ）を 1〜2 文で必ず書く
- 「動作確認」欄は未チェックの雛形として出力し、中身の記入・テスト結果の反映は人が行う
- 本文にコマンドと出力を貼るときは、貼る形のコマンドを直前にそのまま実行して出力を写す（記憶から組み立てない）。CI と同じと書くなら CI の `run:` を読んで引数まで揃え、揃えられないなら書かない。出力を絞ったら絞ったと書き、実行していないものは「未確認」と書く
- 検証ケースの入力（パス・ID）は実物から選ぶ（パスは `git ls-files`、それ以外は出どころを示す）。glob などの照合は存在しない入力でも成功するので、照合スクリプトには入力が実在するかを確かめて無ければ失敗させる処理を入れる。架空の値が要るなら架空と明記する
- 書式（コミットのリンク、太字の閉じ方）は `dotfiles-review-and-act` の「返信と本文の書式」に従う

## draft / ready

- **既定: draft で作成**（`gh pr create --draft`）
- 引数に `ready` 等が指定された場合のみ Ready（`--draft` を付けない）で作成

## reviewer / label / assignee

- 既定では一切付けない（CODEOWNERS や GitHub 側の自動ルールに委ねる）
- 引数で指定されたときのみ `--reviewer` / `--label` / `--assignee` を渡す

## 実行例

```bash
# 既定（draft, デフォルトブランチ向け, reviewer/label 無し）
gh pr create --draft --base "$BASE" --title "$TITLE" --body-file "$BODY_FILE"

# ready + reviewer 指定の例
gh pr create --base "$BASE" --title "$TITLE" --body-file "$BODY_FILE" --reviewer alice,bob
```

作成後は PR の URL を報告する。

## PR サイズ

- PR が大きくなりすぎないよう分割を促す。差分は目安として 500 行以内、最大でも 1000 行程度に収める。
- 関心が異なる変更（例: モデル追加とコントローラ追加）は別 PR に分けることを検討する（レビュー負荷を下げ、レビュー品質を保つため）。

## 方針

- lint / test / review は走らせない（`dotfiles-lint-and-test` ・ review 系スキルの責務）
- commit / push は行わない（`dotfiles-commit-push` の責務）
