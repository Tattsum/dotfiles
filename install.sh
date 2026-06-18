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

echo ""
echo "------------------------------"
echo "🧩 Claude Code のグローバル skill をリンクします..."
echo "------------------------------"
mkdir -p "$HOME/.claude/skills"
for skill_dir in "$DOTFILES_DIR"/skills/src/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  # ディレクトリリンクは -n を付けて既存リンク先への潜り込みを防ぐ
  ln -sfn "$skill_dir" "$HOME/.claude/skills/$skill_name"
  echo "  ✅ $HOME/.claude/skills/$skill_name -> $skill_dir"
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

# tmux / vim / Gemini / Codex などは、設定ファイルを追加したタイミングで
# この下に同様の `link_file` 呼び出しを追記していく運用を想定しています。
# 例）tmux:
# echo ""
# echo "------------------------------"
# echo "🪟 tmux の設定をリンクします..."
# echo "------------------------------"
# link_file "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"

echo ""
echo "✅ セットアップ完了！"

