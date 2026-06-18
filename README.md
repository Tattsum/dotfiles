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

## ターミナル IDE 環境（zellij + helix + yazi）

zellij をベースにしたターミナル IDE 環境を管理しています。

- `zellij/config.kdl` — zellij のデフォルトレイアウトを `ide` に設定
- `zellij/layouts/ide.kdl` — Editor / Implement / Review ペインからなる IDE レイアウト
- `helix/config.toml` — helix のキーマップ（`C-y` で yazi をフローティング起動）
- `helix/yazi-picker.sh` — yazi で選択したファイルを helix で開くためのスクリプト
- `bin/ide` — プロジェクト選択 → zellij セッション attach を行う起動スクリプト（`~/.local/bin/ide` にリンク）

これらは `install.sh` 実行時に `~/.config/zellij`・`~/.config/helix`・`~/.local/bin` 配下へシンボリックリンクされます。
`bin/ide` を使うには `~/.local/bin` が `PATH` に含まれている必要があります。

## その他のツール設定

- `git/.gitignore_global` — git のグローバル除外設定（`.gitconfig` の `core.excludesfile` が参照）
- `kitty/` — kitty ターミナルの設定一式（`kitty.conf`・テーマ・スクリプト）。`~/.config/kitty/` 配下へ個別にリンク
- `zed/settings.json` — Zed エディタの個人設定
- `gh/config.yml` — GitHub CLI の設定。**注意**: `gh` は設定変更時にこのファイルを置き換えることがあり、その際 symlink が解除される。気づいたら `./install.sh` を再実行する

## Homebrew パッケージ（Brewfile）

- `brew/Brewfile` に formula・cask・tap を記録しています（`brew bundle dump` で生成）。
- `install.sh` 実行時、`brew` があれば `brew bundle install` で未導入のものをまとめてインストールします（冪等）。
- **パッケージを追加・削除したら Brewfile を更新する**:
  ```sh
  brew bundle dump --force --file=brew/Brewfile
  ```
- 不要になったパッケージを Brewfile に揃えて削除したい場合（Brewfile に無いものをアンインストール）:
  ```sh
  brew bundle cleanup --file=brew/Brewfile        # 削除対象の確認
  brew bundle cleanup --force --file=brew/Brewfile  # 実行
  ```

## Cursor / Skills（汎用テンプレ）

- **汎用 `.cursorrules`**
  - `cursor/.cursorrules` を用意しています。
  - 各リポジトリに入れたい場合は、そのリポジトリ直下へコピーして使ってください。
- **汎用 Skills**
  - `skills/` 配下に Cursor Agent Skill の雛形を置いています。
  - 任意のリポジトリへ展開する例:
    - `make -C skills install TARGET=/path/to/repo`