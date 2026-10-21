# Claude Code 固有の指示

Claude Code の sandbox とツールを前提にした運用。全エージェント共通の指示は `~/.claude/CLAUDE.md`（dotfiles の `agents/AGENTS.md`）にあり、ここには Codex などに届けても意味が通らないものだけを置く。

## gh の実行と sandbox

- `gh` は単独コマンドで実行するのが基本。`sandbox.excludedCommands` の `gh *` で sandbox 外で動くが、除外が効くのは単独コマンドのときだけ。パイプ・`&&` / `;` / `||`・`$(gh ...)`・ループ・ファイルへのリダイレクト（`>`）・環境変数の前置（`GH_PAGER= gh ...`）のどれかを含むと sandbox 内で動く（`2>&1` と `\` の行継続は可）。整形・絞り込みはまず `--jq` / `-q` / `--limit` など gh 自身のオプションで行い、複数件は1件ずつ別の Bash 呼び出し（並列可）にする。別リポジトリは `cd` せず `--repo owner/repo`（`-R`）で指定する
- パイプ等がどうしても要る gh は、Bash の `allowed_domains` に `api.github.com` を宣言して sandbox 内で実行する（settings の `SSL_CERT_FILE` で sandbox 内でも gh の TLS 検証が通る）。`dangerouslyDisableSandbox` で再試行しない（auto mode に Safety Bypass として拒否される）。`api.github.com` を settings の常時許可には足さない（sandbox 内は審査なしで通りうるので、都度宣言して審査を受ける）。`gh run view --log` のようにログ・成果物を別ホストから取るものは単独で実行し、絞り込みは長い出力が保存されたファイルに対して別の呼び出しで `rg` をかける

## git の作業ツリーと sandbox

sandbox の書き込み禁止パス（このセッションの Bash ツールの説明にある denyWithinAllow が正本。`.claude/` 配下の settings・skills・commands・hooks・agents、`.mcp.json`、`~/.claude/` から symlink されている正本側のファイルなど）は、git も書き換えられない。

- 対象: 作業ツリーを書き換える git 操作。`switch`・`checkout`・`pull`・`merge`・`worktree add` で観測しており、`restore`・`reset --hard`・`rebase`・`stash pop` も同じ仕組みで止まりうる
- 症状: 禁止パスのファイルだけ更新できずに途中で止まり、HEAD・index・作業ツリーが食い違う。exit 0 で終わることがあり、出力が `D<TAB>path` の羅列だけだったり、触っていないのに大量の staged 差分が出たりしたら、これを疑う
- 事前の確認: 実行前に `git diff --name-only HEAD <切替先>`（pull なら fetch 後の `origin/<ブランチ>`）が禁止パスに当たるかを見る。判定の正本は上の denyWithinAllow で、`rg '(^|/)\.claude/|\.mcp\.json$|settings(\.local)?\.json$|(^|/)(AGENTS|CLAUDE)\.md$|(^|/)rules/'` は網羅ではない目安
- 当たるなら、最初から sandbox 外（`dangerouslyDisableSandbox`）で実行する。上の gh の規則は sandbox 内で失敗した後の再試行についてで、こちらは失敗すると分かっている操作の事前の例外。この節で sandbox 外と書いた操作が auto mode に拒否されたら、コマンドを示して利用者に `!` で実行してもらう
- 止まってしまったら、`git status` と `git rev-parse --abbrev-ref HEAD` でずれ方を確かめる。`git status` の全項目について、利用者の編集が混ざっていないか（禁止パスの差分は `git diff <切替先> -- <ファイル>` が空か）を確かめ、混ざっていれば先に別名のコピーで退避する（`git stash` も作業ツリーを書き換えるので、使うなら sandbox 外で）。そのうえで sandbox 外で揃える。switch / checkout は `git checkout -f <ブランチ名>`（`origin/<x>` を渡すと detached になる）、pull / merge は `git checkout -f HEAD` で今のブランチに戻してから同じ pull / merge をやり直す。切替先で増えた追跡外のファイルの `git clean` は利用者に任せる
- `.git/config` にも書けない。sandbox 内の `git branch -d` は exit 128 になるが ref は消えており、`branch.<名前>.*` の追跡設定だけが残る。掃除は sandbox 外で `git config --remove-section branch.<名前>`。追跡設定を書く操作（`git switch -c <b> origin/<x>`・`git branch --set-upstream-to` など）も sandbox 外で実行する

## 一時ファイルと sandbox

- `$TMPDIR` は sandbox の内と外で別の場所を指す。sandbox 内で作ったファイルを sandbox 外で動くコマンド（excludedCommands に一致した `gh` など）に渡すときは、sandbox 内で得た絶対パスをリテラルで書く（`$TMPDIR` を外側で展開させない）。外側では別のファイルを読むので、`gh pr edit --body-file` のように本文を丸ごと置き換える操作は、成功が返っても中身が違うことがある。先に旧本文を保存し、実行後に `gh pr view --json body` で読み戻して照合する
- macOS の `mktemp -d`（引数なし）と `mktemp -t` は TMPDIR を使わず `/var/folders` に作るので、sandbox 内では `mktemp -d "${TMPDIR:-/tmp}/<名前>.XXXXXX"` の形で書く
- sandbox 内のプロセス置換 `<(...)` は、`/dev/fd` を許可しても `Operation not permitted` で失敗する（設定では直らない）。`$TMPDIR` に中間ファイルを書いてから渡す

## AWS と本番

- sandbox 内の AWS CLI は SSO のキャッシュ（`~/.aws/cli/cache`）に書けない。`aws sso login` の直後はすべての aws コマンドがこれで落ちる。そうでなくても ECS などの API はプロキシで拒否される（`rds-data` と `logs` は通る。プロキシへの接続エラーなら sandbox、AWS の API エラーなら疎通できている）
- sandbox 内で失敗しても `dangerouslyDisableSandbox` で再試行せず、次の手順に移る。読み取り専用なら通った例もあるが、分類器に拒否されてしばらく読み取りの Bash まで拒否された例がある。本番への書き込み（`run-task` など）と秘密の列挙（`secretsmanager list-secrets`）は拒否される
- 確実な手順: 利用者に `!` で実行してもらう。読み取りは describe・list・Logs Insights だけのスクリプトを scratchpad に書き、中身の要約を添えて渡す。本番への書き込みは、復唱と事前チェックまでを行い、コマンドそのものを渡す
