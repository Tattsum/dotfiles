#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🔧 dotfiles のセットアップを開始します..."
echo "   DOTFILES_DIR: $DOTFILES_DIR"
echo ""

link_file() {
  local src="$1"
  local dest="$2"

  mkdir -p "$(dirname "$dest")"

  ln -sf "$src" "$dest"
  echo "  ✅ $dest -> $src"
}

echo "------------------------------"
echo "📝 Claude Code の設定をリンクします..."
echo "------------------------------"
link_file "$DOTFILES_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
link_file "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json"
link_file "$DOTFILES_DIR/claude/statusline.sh" "$HOME/.claude/statusline.sh"
link_file "$DOTFILES_DIR/claude/subagent-statusline.sh" "$HOME/.claude/subagent-statusline.sh"
link_file "$DOTFILES_DIR/claude/agents/Explore.md" "$HOME/.claude/agents/Explore.md"

echo ""
echo "------------------------------"
echo "🤖 Codex の運用ルールをリンクします..."
echo "------------------------------"
# Claude Code と Codex で運用ルールの正本を共有する。Codex は
# ~/.codex/AGENTS.md をグローバル指示として読み込む。
link_file "$DOTFILES_DIR/claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"

echo ""
echo "------------------------------"
echo "🧩 Claude Code / Cursor / Codex のグローバル skill をリンクします..."
echo "------------------------------"
# skills/src を正本とし、各エージェントへ同じ skill を symlink する。
# これにより各ツールで同一の skill を使い回せる（編集の正本は skills/src のみ）。
mkdir -p "$HOME/.claude/skills" "$HOME/.cursor/skills" "$HOME/.agents/skills"
for skill_dir in "$DOTFILES_DIR"/skills/src/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  # skill_name が空だと直下の rm -rf が skills ディレクトリごと消す。glob の性質上
  # 現状は空にならないが、$HOME 配下の再帰削除に暗黙の前提を残さない。
  [ -n "$skill_name" ] || continue
  # 配置前に rm -rf する。ln -sfn は宛先が実ディレクトリの場合エラーにならず、
  # ディレクトリの「中」に symlink を作って入れ子（dest/name/name）を生やすため、
  # -n だけでは過去の cp 配置や前回の入れ子が残り続ける。
  rm -rf "$HOME/.claude/skills/$skill_name" "$HOME/.cursor/skills/$skill_name" "$HOME/.agents/skills/$skill_name"
  ln -sfn "$skill_dir" "$HOME/.claude/skills/$skill_name"
  ln -sfn "$skill_dir" "$HOME/.cursor/skills/$skill_name"
  ln -sfn "$skill_dir" "$HOME/.agents/skills/$skill_name"
  echo "  ✅ $HOME/.claude/skills/$skill_name -> $skill_dir"
  echo "  ✅ $HOME/.cursor/skills/$skill_name -> $skill_dir"
  echo "  ✅ $HOME/.agents/skills/$skill_name -> $skill_dir"
done

# 正本（skills/src）から削除された skill の symlink を掃除する。上のループは張り直すだけで
# 消えた skill には触れないため、放置すると壊れた symlink を各エージェントが読み続ける。
# symlink かつリンク先が skills/src 配下かつ実在しないものだけを対象にし、実ディレクトリ・
# プラグイン由来の配置・他ツールが置いたものには触れない。
for agent_skills_dir in "$HOME/.claude/skills" "$HOME/.cursor/skills" "$HOME/.agents/skills"; do
  for entry in "$agent_skills_dir"/*; do
    [ -L "$entry" ] || continue
    case "$(readlink "$entry")" in
      "$DOTFILES_DIR"/skills/src/*) ;;
      *) continue ;;
    esac
    [ -e "$entry" ] && continue
    rm -f "$entry"
    echo "  🧹 $entry を削除（正本が存在しない）"
  done
done

echo ""
echo "------------------------------"
echo "🐚 zsh の設定をリンクします..."
echo "------------------------------"
link_file "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"

echo ""
echo "------------------------------"
echo "⚙️ git の設定をリンクします..."
echo "------------------------------"
link_file "$DOTFILES_DIR/git/.gitconfig" "$HOME/.gitconfig"

echo ""
echo "------------------------------"
echo "📝 Cursor の設定をリンクします..."
echo "------------------------------"
link_file "$DOTFILES_DIR/cursor/cursor.toml" "$HOME/.config/cursor/cursor.toml"

echo ""
echo "------------------------------"
echo "🗂 yazi の設定をリンクします..."
echo "------------------------------"
link_file "$DOTFILES_DIR/yazi/yazi.toml" "$HOME/.config/yazi/yazi.toml"

echo ""
echo "------------------------------"
echo "🧱 zellij の設定をリンクします..."
echo "------------------------------"
link_file "$DOTFILES_DIR/zellij/config.kdl" "$HOME/.config/zellij/config.kdl"
link_file "$DOTFILES_DIR/zellij/layouts/ide.kdl" "$HOME/.config/zellij/layouts/ide.kdl"

echo ""
echo "------------------------------"
echo "✏️ helix の設定をリンクします..."
echo "------------------------------"
link_file "$DOTFILES_DIR/helix/config.toml" "$HOME/.config/helix/config.toml"
link_file "$DOTFILES_DIR/helix/yazi-picker.sh" "$HOME/.config/helix/yazi-picker.sh"

echo ""
echo "------------------------------"
echo "🚀 ide スクリプトをリンクします..."
echo "------------------------------"
link_file "$DOTFILES_DIR/bin/ide" "$HOME/.local/bin/ide"

echo ""
echo "------------------------------"
echo "🧰 skill から呼ぶ共有スクリプトをリンクします..."
echo "------------------------------"
# skill ディレクトリ内ではなく PATH 上に置く。skill は ~/.claude/skills・
# ~/.cursor/skills・TARGET/.cursor/skills の3系統に配られるため、skill 内に
# 置くと参照側にパス解決のフォールバックが要る。コマンド名で呼べば1行で済む。
link_file "$DOTFILES_DIR/bin/skill-resolve-diff" "$HOME/.local/bin/skill-resolve-diff"
link_file "$DOTFILES_DIR/bin/skill-review-state" "$HOME/.local/bin/skill-review-state"
link_file "$DOTFILES_DIR/bin/skill-session-digest" "$HOME/.local/bin/skill-session-digest"
link_file "$DOTFILES_DIR/bin/skill-nippo-notion-post" "$HOME/.local/bin/skill-nippo-notion-post"

echo ""
echo "------------------------------"
echo "🕒 launchd ジョブのスクリプトをリンクします..."
echo "------------------------------"
link_file "$DOTFILES_DIR/bin/brew-maintenance" "$HOME/.local/bin/brew-maintenance"
link_file "$DOTFILES_DIR/bin/install-launchagent" "$HOME/.local/bin/install-launchagent"

echo ""
echo "------------------------------"
echo "📊 prompt-pattern-scan の解析バッチをリンクします..."
echo "------------------------------"
# state.json / report-latest.md / classification-rules.json は history.jsonl の派生物で
# 社内固有名を含むため repo に置かない。ここでリンクするのはロジック側だけ。
link_file "$DOTFILES_DIR/claude/prompt-patterns/ANALYSIS_PROMPT.md" "$HOME/.claude/prompt-patterns/ANALYSIS_PROMPT.md"
link_file "$DOTFILES_DIR/claude/prompt-patterns/run-analysis.sh" "$HOME/.claude/prompt-patterns/run-analysis.sh"
link_file "$DOTFILES_DIR/claude/prompt-patterns/README.md" "$HOME/.claude/prompt-patterns/README.md"

echo ""
echo "------------------------------"
echo "⭐ starship の設定をリンクします..."
echo "------------------------------"
link_file "$DOTFILES_DIR/starship/starship.toml" "$HOME/.config/starship.toml"

echo ""
echo "------------------------------"
echo "⚙️ git のグローバル除外設定をリンクします..."
echo "------------------------------"
link_file "$DOTFILES_DIR/git/.gitignore_global" "$HOME/.gitignore_global"

echo ""
echo "------------------------------"
echo "🐱 kitty の設定をリンクします..."
echo "------------------------------"
for kitty_file in "$DOTFILES_DIR"/kitty/*; do
  link_file "$kitty_file" "$HOME/.config/kitty/$(basename "$kitty_file")"
done

echo ""
echo "------------------------------"
echo "⚡ Zed の設定をリンクします..."
echo "------------------------------"
link_file "$DOTFILES_DIR/zed/settings.json" "$HOME/.config/zed/settings.json"
link_file "$DOTFILES_DIR/zed/keymap.json" "$HOME/.config/zed/keymap.json"

echo ""
echo "------------------------------"
echo "🐙 gh (GitHub CLI) の設定をリンクします..."
echo "------------------------------"
# 注意: gh は設定変更時にこのファイルを置き換える（atomic rename）ことがあり、
# その場合 symlink が解除され実ファイルに戻る。気づいたら ./install.sh を再実行する。
link_file "$DOTFILES_DIR/gh/config.yml" "$HOME/.config/gh/config.yml"

# tmux / vim / Gemini などは、設定ファイルを追加したタイミングで
# この下に同様の `link_file` 呼び出しを追記していく運用を想定しています。
# 例）tmux:
# echo ""
# echo "------------------------------"
# echo "🪟 tmux の設定をリンクします..."
# echo "------------------------------"
# link_file "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"

echo ""
echo "------------------------------"
echo "🍺 Homebrew パッケージ（Brewfile）を適用します..."
echo "------------------------------"
if command -v brew >/dev/null 2>&1; then
  # bundle install は未導入を入れるだけでなく outdated な cask も更新する。bin/brew-maintenance と
  # 同じ抑制を効かせないと、セットアップのたびに起動中の Docker Desktop やエディタが落とされ、
  # 自己更新するアプリを brew が二重に上書きする。
  export HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1
  export HOMEBREW_NO_UPGRADE_QUIT_CASKS=1

  # 冪等。インストール済みは skip され、未導入の formula/cask/tap のみ入る。
  brew bundle install --file="$DOTFILES_DIR/brew/Brewfile"
else
  echo "  ⏭ brew が見つからないためスキップ（https://brew.sh からインストール後に再実行）"
fi

echo ""
echo "------------------------------"
echo "🧩 Codex の Atlassian MCP を設定します..."
echo "------------------------------"
if ! "$DOTFILES_DIR/bin/configure-codex-atlassian"; then
  echo "  ⚠️ Atlassian MCP 設定は完了しませんでしたが、他のセットアップを続行します"
fi

echo ""
echo "------------------------------"
echo "🕒 launchd ジョブを登録します..."
echo "------------------------------"
# 失敗を許容する。bootstrap は disable 済み・二重ロードのいずれでも exit 5 を返し、
# set -e 下でそのまま呼ぶとこのセットアップ全体が落ちる。
if ! "$DOTFILES_DIR/bin/install-launchagent"; then
  echo "  ⚠️ launchd ジョブの登録に失敗しました。上のメッセージを確認して"
  echo "     install-launchagent を単独で再実行してください（他の設定は適用済みです）"
fi

echo ""
echo "✅ セットアップ完了！"
