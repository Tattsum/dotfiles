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

