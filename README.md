dotfiles 管理用リポジトリです。

## セットアップ手順

- **初回 / マシン変更時**
  - このリポジトリを任意の場所に clone します（例：`~/workspace/dotfiles`）
  - リポジトリ直下で以下を実行します：
    - `chmod +x ./install.sh`
    - `./install.sh`

## `install.sh` の方針

- `DOTFILES_DIR` からホームディレクトリ配下へ **シンボリックリンクを張る** ことで設定を一元管理します。
- 共通関数 `link_file <src> <dest>` を使ってリンクを作成します。
  - 例：`link_file "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"`

## 設定を追加したいとき

- 例：`zsh` の設定を管理したい場合
  - `zsh/.zshrc` をこのリポジトリに追加
  - `install.sh` に以下のようなブロックを追記：
    - `echo ""`
    - `echo "------------------------------"`
    - `echo "🐚 zsh の設定をリンクします..." `
    - `echo "------------------------------"`
    - `link_file "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"`

この README と `install.sh` をベースに、必要な設定を少しずつ追加していく想定です。

## Cursor / Skills（汎用テンプレ）

- **汎用 `.cursorrules`**
  - `cursor/.cursorrules` を用意しています。
  - 各リポジトリに入れたい場合は、そのリポジトリ直下へコピーして使ってください。
- **汎用 Skills**
  - `skills/` 配下に Cursor Agent Skill の雛形を置いています。
  - 任意のリポジトリへ展開する例:
    - `make -C skills install TARGET=/path/to/repo`