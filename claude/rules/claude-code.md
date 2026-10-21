# Claude Code 固有の指示

Claude Code の sandbox とツールを前提にした運用。全エージェント共通の指示は `~/.claude/CLAUDE.md`（dotfiles の `agents/AGENTS.md`）にあり、ここには Codex などに届けても意味が通らないものだけを置く。

## gh の実行と sandbox

- `gh` は単独コマンドで実行するのが基本。`sandbox.excludedCommands` の `gh *` で sandbox 外で動くが、除外が効くのは単独コマンドのときだけ。パイプ・`&&` / `;` / `||`・`$(gh ...)`・ループ・ファイルへのリダイレクト（`>`）・環境変数の前置（`GH_PAGER= gh ...`）のどれかを含むと sandbox 内で動く（`2>&1` と `\` の行継続は可）。整形・絞り込みはまず `--jq` / `-q` / `--limit` など gh 自身のオプションで行い、複数件は1件ずつ別の Bash 呼び出し（並列可）にする。別リポジトリは `cd` せず `--repo owner/repo`（`-R`）で指定する
- パイプ等がどうしても要る gh は、Bash の `allowed_domains` に `api.github.com` を宣言して sandbox 内で実行する（settings の `SSL_CERT_FILE` で sandbox 内でも gh の TLS 検証が通る）。`dangerouslyDisableSandbox` で再試行しない（auto mode に Safety Bypass として拒否される）。`api.github.com` を settings の常時許可には足さない（sandbox 内は審査なしで通りうるので、都度宣言して審査を受ける）。`gh run view --log` のようにログ・成果物を別ホストから取るものは単独で実行し、絞り込みは長い出力が保存されたファイルに対して別の呼び出しで `rg` をかける
