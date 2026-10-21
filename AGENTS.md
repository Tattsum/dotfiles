# dotfiles

ホームディレクトリの設定を symlink で配る dotfiles。セットアップ手順と各設定の説明は README.md。

- 正本はこのリポジトリにある。`~/.claude/`・`~/.codex/`・`~/.agents/`・`~/.cursor/` などの配布先は `install.sh` が張る symlink なので、配布先を直接編集しない。
  - 全エージェント共通のグローバル指示: `agents/AGENTS.md`
  - Claude Code だけのグローバル指示: `claude/rules/`
  - skill: `skills/src/<skill-id>/`、skill から呼ぶスクリプト: `bin/skill-*`
- 設定ファイルを増やしたら `install.sh` に `link_file` を足す。`install.sh` は `~` 配下に書き込むので、実行は人間に頼む。
- `bin/` のスクリプトを変えたら、対応する `tests/<name>-test.sh` を実行する。
- public リポジトリなので、社内の固有名・社内リポジトリ名・絶対パス・トークンを書かない。
