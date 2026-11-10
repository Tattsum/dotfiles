---
name: dotfiles-commit-split
description: 変更を「1 コミット = 1 つの処理の流れ」のコミット列に分ける・分け直すとき。まだコミットしていない作業ツリーの分割と、1 つにまとまってしまった既存のコミットの分け直し（履歴の書き換え。元の author と author date をできるだけ保つ）を受け持つ。dotfiles-commit-push から呼ばれるほか、「コミットを整理して」「commit log を綺麗に整理して」「コミットを分けて」「1 コミットにまとまったのを分け直して」等で発動。1 つのコミットを作るだけの「コミットして」には使わない（dotfiles-commit-push）。
---

## 目的

変更を、あとから参照しやすいコミット列にする。分け方の基準はグローバル指示（`AGENTS.md`）の「コミットの分け方」に従い、ここには書かない。各コミットの秘密情報チェック・メッセージ規約・保護ブランチの扱いは `dotfiles-commit-push` に従う。

以下では、1 つの処理の流れとして 1 コミットに入れる変更の集まりを「グループ」と呼ぶ。

## 対象と確認の要否

| 対象 | 確認 | 基点 `<base>` |
|---|---|---|
| 作業ツリーの未コミットの変更 | 不要（履歴を書き換えない） | `HEAD` |
| 未 push のコミット | 不要（退避 ref から戻せる手元だけの操作） | `@{u}`。upstream が無ければ `git merge-base <デフォルトブランチ> HEAD` |
| push 済みのコミット | 分割案と影響（force push）を示し、利用者の確認を得てから | `git merge-base <デフォルトブランチ> HEAD` |
| レビューコメントが付いた PR のコミット | 利用者が明示したときだけ。こちらから提案しない（返信に貼ったコミットのリンクが切れるため） | 同上 |

`dotfiles-commit-push` から呼ばれたときは、未 push までを対象にする。push 済みのコミットも分け直したほうがよいと判断したら、表に従って提案するか見送る。

利用者が直接「整理して」と頼んだときも、push 済みを書き換えるなら、force push の前に分割案を示して確認する。

レビューコメントの有無は次のコマンドで見る（単独の Bash 呼び出し）。1 以上なら付いたとみなし、PR が無ければ 0 とみなす。

```bash
gh pr view --json reviews,comments -q '(.reviews | length) + (.comments | length)'
```

## 使わないコマンド

- `git rebase -i` / `git add -p`: 対話型なので止まる。
- `git reset --hard` / `git checkout` / `git switch` / `git rebase`: 作業ツリーを書き換えるので、sandbox の書き込み禁止パスのファイルで途中で止まる。`rebase` は新しいコミットを sandbox 内で作るので、署名にも失敗する。HEAD とインデックスだけを動かす `git reset --mixed` は使う。
- `git branch <退避名>`: 退避は `refs/backup/` に置く。ブランチ一覧を汚さず、消すときに sandbox から書けない `.git/config` に触れずに済む。

## 手順

### 1. 範囲と元の情報を控える

保護ブランチ上なら、先に `dotfiles-commit-push` の「保護ブランチ上での分岐」に従う。

既存のコミットを分け直すときは、次の 2 点を確かめる。満たさなければ止めて報告する。

- `git rev-list --merges <base>..HEAD` が空（範囲にマージコミットが無い）。
- 基点が `@{u}` なら、`git merge-base --is-ancestor @{u} HEAD` の終了コードが 0（ローカルで rebase して、リモートと分岐していない）。

元の情報を控える。

```bash
git log --reverse --format='%H%x09%an <%ae>%x09%aI%x09%s' <base>..HEAD
git diff --stat <base> HEAD
git rev-parse @{u}
```

最後の SHA（書き換え前のリモートの位置）は、手順 6 の force push で使う。upstream が無ければ控えなくてよい。

既存のコミットを分け直すとき、未コミットの変更が残っていれば、範囲に含めるかを決める。`dotfiles-commit-push` から呼ばれたときは含める（呼び出し元がコミットしようとしている変更なので）。直接頼まれたときは利用者に確認する。

含めるなら、一時コミットにする。追跡中のファイルは `git add -u` で、追跡外の新規ファイルは `git add -- <path>` でステージする。そのうえで `git commit -m "WIP: temporary commit before split"` を単独で実行する（メッセージは英語。退避 ref には残るため）。一時コミットは手順 2 の巻き戻しで消え、その変更も退避 ref と手順 5 の一致確認の対象になる。

### 2. 退避して巻き戻す（既存のコミットを分け直すときだけ）

```bash
git update-ref refs/backup/<ブランチ名>-split HEAD
git reset -q --mixed <base>
```

HEAD とインデックスだけが基点に戻り、作業ツリーは元の最終状態のまま残る。元のコミットで追加したファイルは、ここで追跡外（`??`）になる。ここから先は、作業ツリーからの分割と同じ手順になる。

### 3. 分割案を立てる

`git diff` と `git status --short`（追跡外の新規ファイルを含む）で変更全体を読む。基準に沿ってグループに分け、並び順を決める。グループごとに、含めるファイルとハンク、コミットの Title を一覧にする。push 済みを書き換えるときは、ここで一覧を示して確認を待つ。

### 4. グループごとにステージしてコミットする

ステージする。

- ファイルを丸ごと入れる: `git add -- <path>...`（新規ファイルの追加も、削除の反映もこれで入る）
- ハンク単位で入れる: `git diff -- <path>` をファイルに書き、このグループに入れないハンクを消してから当てる。

```bash
git apply --cached --recount <パッチの絶対パス>
```

パッチを削るときは、ハンクを `@@` 行から次の `@@` 行の手前まで丸ごと消す。ハンクの中を削るなら、`+` 行は消し、`-` 行は先頭を空白にして文脈行に変える。新規ファイルの一部だけを入れることはせず、丸ごと `git add` する。

ステージしたら、`git diff --cached --stat` と `git diff --cached` で、そのグループの変更だけが入っているかを確かめる。あわせて、`dotfiles-commit-push` の秘密情報チェックを `git diff --cached` に対して行う。

コミットする。メッセージは `dotfiles-commit-push` の規約で書く。

```bash
git commit --author="Jane Doe <jane@example.com>" --date="2026-01-02T03:04:05+09:00" -F <メッセージファイルの絶対パス>
```

- `git commit` は単独の Bash 呼び出しにし、値はすべて展開済みのリテラルで書く。`$(...)`・環境変数の前置（`GIT_AUTHOR_DATE=...`）・`&&` を含めると、sandbox 除外の `git commit *` に一致しない。その場合は sandbox 内で動き、署名に失敗する。
- メッセージファイルは sandbox 内で作り、sandbox 外で動く `git commit` には絶対パスをリテラルで渡す（`$TMPDIR` は内と外で指す場所が違う）。
- committer と committer date は、今の利用者と時刻のままにする。

author と author date は次のように決める。

- 作業ツリーからの分割と、一時コミットに由来する変更: `--author` / `--date` を付けない（今の設定と今の時刻）。
- 既存のコミットを分け直したとき: グループに入るファイルの元のコミットを、次のコマンドで調べる。

  ```bash
  git log --reverse --format='%H%x09%an <%ae>%x09%aI' <base>..refs/backup/<ブランチ名>-split -- <path>...
  ```

  一時コミットの行を除き、出力の先頭（範囲の中で最初に積まれたコミット）の author と author date を渡す。`rebase -i` の squash が先頭のコミットの author を残すのと同じ扱いにする。帰属はファイル単位で見て、同じファイルの中のハンクを誰が書いたかまでは追わない。1 つの元のコミットを分けたなら、全部のコミットが同じ値を引き継ぐ。
- 出力に他の author がいれば、メッセージ末尾に `Co-authored-by: Jane Doe <jane@example.com>` の形で 1 人 1 行ずつ足す。
- 元のコミットと同じ変更をそのまま含むグループは、メッセージごと再利用してよい（`git commit -C <元の SHA>`）。

### 5. 検証する

- 既存のコミットを分け直したとき、`git diff --quiet refs/backup/<ブランチ名>-split HEAD` の終了コードが 0（木が一致している）。
- 分けた変更が `git status --short` に残っていない（コミット漏れが無い）。
- `git log --format='%h %an <%ae> %aI %s' <base>..HEAD` で、並び順と author / author date を手順 1 の控えと突き合わせ、`Co-authored-by` の付け忘れも見る。木の一致では、これらの誤りを検出できない。
- 最後のコミットで lint/test を回す（`dotfiles-lint-and-test`。PHP なら `dotfiles-php-laravel-lint-test`）。中間のコミットのビルドとテストは確かめない。並べ方で担保し、保証していないことを報告に書く。

一致しなければ `git reset -q --mixed refs/backup/<ブランチ名>-split` で HEAD とインデックスを元に戻す。手順の間は作業ツリーを書き換えていないので、作業ツリーも元のままになる。そのうえで、ずれた内容を報告する。

### 6. push と後始末

未 push の範囲だけを分けたなら、ここで終える。push するときは `dotfiles-commit-push` に戻る。

push 済みを書き換えたとき（確認は手順 3 で得ている）は、次の順に進む。

1. `git fetch origin <ブランチ名>` を単独で実行する。
2. `git rev-parse origin/<ブランチ名>` が、手順 1 で控えた SHA と一致するかを確かめる。違えば、ほかの push が入っているので止めて報告する。
3. `git push --force-with-lease=<ブランチ名>:<控えた SHA> origin <ブランチ名>` を単独で実行する。期待する SHA を明示するのは、エディタなどの自動 fetch で追跡ブランチが進むと、素の `--force-with-lease` では保護にならないため。保護ブランチには force push しない。
4. auto mode で拒否されたら、コマンドを示して利用者に `!` で実行してもらう。
5. PR があれば、`gh pr checks` で CI の全件が通ったのを見てから完了とする。

退避 ref は消さずに残し、そのことと、消すコマンド（`git update-ref -d refs/backup/<ブランチ名>-split`）を報告に添える。消すのはマージの後でよい。
